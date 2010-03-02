require 'hpricot'

class Roll
  include MongoMapper::Document
  
  key :roll_id, String, :required => true
  key :chamber, String, :required => true
  key :session, String, :required => true
  key :result, String, :required => true
  
  timestamps!
  
  ensure_index :roll_id
  ensure_index :chamber
  ensure_index :session
  ensure_index :type
  ensure_index :result
  ensure_index :voted_at
  ensure_index :type
  ensure_index :bill_id
  
  def self.unique_keys
    [:roll_id]
  end
  
  def self.search_keys
    [:bill_id, :chamber, :session]
  end
  
  def self.fields
    {
      :basic => [:roll_id, :number, :year, :chamber, :session, :result, :bill_id, :voted_at, :updated_at, :type, :question, :required, :vote_breakdown],
      :party_vote_breakdown => [:party_vote_breakdown],
      :voter_ids => [:voter_ids],
      :voters => [:voters],
      :bill => [:bill]
    }
  end
  
  def self.voter_fields
    [:first_name, :nickname, :last_name, :name_suffix, :title, :state, :party, :district, :govtrack_id, :bioguide_id]
  end
  
  def self.bill_fields
    Bill.fields[:basic]
  end

  def self.update(session = nil)
    session ||= Bill.current_session
    count  = 0
    missing_ids = []
    bad_rolls = []
    
    start = Time.now
    
    FileUtils.mkdir_p "data/govtrack/#{session}/rolls"
    unless system("rsync -az govtrack.us::govtrackdata/us/#{session}/rolls/ data/govtrack/#{session}/rolls/")
      Report.failure self, "Couldn't rsync to Govtrack.us."
      return
    end
    
    
    # make lookups faster later by caching a hash of legislators from which we can lookup govtrack_ids
    legislators = {}
    Legislator.all(:fields => [:first_name, :nickname, :last_name, :name_suffix, :title, :state, :party, :govtrack_id, :bioguide_id]).each do |legislator|
      legislators[legislator.govtrack_id] = legislator
    end
    
    
    # Debug helpers
    rolls = Dir.glob "data/govtrack/#{session}/rolls/*.xml"
    # rolls = Dir.glob "data/govtrack/#{session}/rolls/h2009-2.xml"
    # rolls = rolls.first 20
    
    rolls.each do |path|
      doc = Hpricot::XML open(path)
      
      filename = File.basename path
      matches = filename.match /^([hs])(\d+)-(\d+)\.xml/
      year = matches[2]
      number = matches[3]
      
      roll_id = "#{matches[1]}#{number}-#{year}"
      
      if roll = Roll.first(:conditions => {:roll_id => roll_id})
        # puts "[Roll #{roll_id}] About to be updated"
      else
        roll = Roll.new :roll_id => roll_id
        # puts "[Roll #{roll_id}] About to be created"
      end
      
      bill_id = bill_id_for doc
      voter_ids, voters = votes_for doc, legislators, missing_ids
      party_vote_breakdown = vote_breakdown_for voters
      vote_breakdown = party_vote_breakdown.delete :total
      
      roll.attributes = {
        :filename => filename,
        :chamber => doc.root['where'],
        :year => year,
        :number => number,
        :session => session,
        :result => doc.at(:result).inner_text,
        :bill_id => bill_id,
        :voted_at => Time.parse(doc.root['datetime']),
        :type => doc.at(:type).inner_text,
        :question => doc.at(:question).inner_text,
        :required => doc.at(:required).inner_text,
        :bill => bill_for(bill_id),
        :voter_ids => voter_ids,
        :voters => voters,
        :vote_breakdown => vote_breakdown,
        :party_vote_breakdown => party_vote_breakdown
      }
      
      if roll.save
        count += 1
      else
        bad_rolls << {:attributes => roll.attributes, :error_messages => roll.errors.full_messages}
      end
    end
    
    Report.success self, "Synced #{count} roll calls for session ##{session} from GovTrack.us.", {:elapsed_time => Time.now - start}
    
    if bad_rolls.any?
      Report.failure self, "Failed to save #{bad_rolls.size} roll calls. Attached the last failed roll's attributes and error messages.", bad_rolls.last
    end
    
    if missing_ids.any?
      missing_ids = missing_ids.uniq
      Report.warning self, "Found #{missing_ids.size} missing GovTrack IDs, attached. Vote counts on roll calls may be inaccurate until these are fixed.", {:missing_ids => missing_ids}
    end
    
    count
  rescue Exception => exception
    Report.failure self, "Exception while saving Rolls. Attached exception to this message.", {:exception => {:backtrace => exception.backtrace, :message => exception.message}}
  end
  
  def self.bill_id_for(doc)
    if bill = doc.at(:bill)
      bill_id = "#{Bill.type_for bill['type']}#{bill['number']}-#{bill['session']}"
    end
  end
  
  def self.bill_for(bill_id)
    bill = Bill.first :conditions => {:bill_id => bill_id}, :fields => bill_fields
    
    if bill
      attributes = bill.attributes
      allowed_keys = bill_fields.map {|f| f.to_s}
      attributes.keys.each {|key| attributes.delete key unless allowed_keys.include?(key)}
      attributes
    else
      nil
    end
  end
  
  def self.vote_mapping
    {
      '-' => :nays, 
      '+' => :ayes, 
      '0' => :not_voting, 
      'P' => :present
    }
  end
  
  def self.vote_breakdown_for(voters)
    breakdown = {:total => {}}
    mapping = vote_mapping
    
    voters.each do|voter|      
      party = voter[:voter]['party']
      vote = mapping[voter[:vote]] || voter[:vote]
      
      breakdown[party] ||= {}
      breakdown[party][vote] ||= 0
      breakdown[:total][vote] ||= 0
      
      breakdown[party][vote] += 1
      breakdown[:total][vote] += 1
    end
    
    parties = breakdown.keys
    votes = (breakdown[:total].keys + mapping.values).uniq
    votes.each do |vote|
      parties.each do |party|
        breakdown[party][vote] ||= 0
      end
    end
    
    breakdown
  end
  
  def self.votes_for(doc, legislators, missing_ids)
    voter_ids = []
    voters = []
    
    doc.search("//voter").each do |elem|
      vote = elem['vote']
      value = elem['value']
      govtrack_id = elem['id']
      voter = voter_for govtrack_id, legislators
      
      if voter
        voter_ids << {:vote => vote, :voter_id => voter[:bioguide_id]}
        voters << {:vote => vote, :voter => voter}
      else
        missing_ids << govtrack_id
      end
    end
    
    [voter_ids, voters.compact]
  end
  
  def self.voter_for(govtrack_id, legislators)
    legislator = legislators[govtrack_id]
    
    if legislator
      attributes = legislator.attributes
      allowed_keys = voter_fields.map {|f| f.to_s}
      attributes.keys.each {|key| attributes.delete key unless allowed_keys.include?(key)}
      attributes
    else
      nil
    end
  end
end