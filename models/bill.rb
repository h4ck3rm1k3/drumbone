require 'hpricot'

class Bill
  include MongoMapper::Document
  
  key :bill_id, String, :required => true
  key :type, String, :required => true
  key :code, String, :required => true
  key :chamber, String, :required => true
  key :session, String, :required => true
  key :state, String, :required => true
  
  ensure_index :bill_id
  ensure_index :type
  ensure_index :code
  ensure_index :chamber
  ensure_index :session
  ensure_index :introduced_at
  ensure_index :sponsor_id
  ensure_index :cosponsor_ids
  ensure_index :keywords
  ensure_index :last_action_at
  ensure_index :last_vote_at
  ensure_index :enacted_at
  ensure_index :enacted
  
  timestamps!
  
  
  def self.unique_keys
    [:bill_id]
  end
  
  def self.search_keys
    [:sponsor_id, :cosponsor_ids, :chamber, :enacted, :session]
  end
  
  def self.basic_fields
    [
      :bill_id, :type, :code, :number, :session, :chamber, :last_updated, :state, 
      :short_title, :official_title, 
      :sponsor_id, :cosponsors_count, :votes_count, :last_action_at, :last_vote_at, 
      :introduced_at, :house_result, :house_result_at, :senate_result, :senate_result_at, :passed, :passed_at,
      :vetoed, :vetoed_at, :override_house_result, :override_house_result_at,
      :override_senate_result, :override_senate_result_at, 
      :awaiting_signature, :awaiting_signature_since, :enacted, :enacted_at
    ]
  end
  
  def self.sponsor_fields
    [:first_name, :nickname, :last_name, :name_suffix, :title, :state, :party, :district, :govtrack_id, :bioguide_id]
  end
  
  # options:
  #   session: The session of Congress to update
  def self.update(options = {})
    session = options[:session] || current_session
    count = 0
    missing_ids = []
    bad_bills = []
    
    start = Time.now
    
    FileUtils.mkdir_p "data/govtrack/#{session}/bills"
    unless system("rsync -az govtrack.us::govtrackdata/us/#{session}/bills/ data/govtrack/#{session}/bills/")
      Report.failure self, "Couldn't rsync to Govtrack.us."
      return
    end
    
    # make lookups faster later by caching a hash of legislators from which we can lookup govtrack_ids
    legislators = {}
    Legislator.all(:fields => sponsor_fields).each do |legislator|
      legislators[legislator.govtrack_id] = legislator
    end
    
    
    
    bills = Dir.glob "data/govtrack/#{session}/bills/*.xml"
    
    # debug helpers
    # bills = Dir.glob "data/govtrack/#{session}/bills/s2968.xml"
    # bills = bills.first 20
    
    bills.each do |path|
      doc = Hpricot::XML open(path)
      
      filename = File.basename path
      type = type_for doc.root.attributes['type']
      number = doc.root.attributes['number']
      code = "#{type}#{number}"
      
      bill_id = "#{code}-#{session}"
      
      if bill = Bill.first(:conditions => {:bill_id => bill_id})
        # puts "[Bill #{bill.bill_id}] About to be updated"
      else
        bill = Bill.new :bill_id => bill_id
        # puts "[Bill #{bill.bill_id}] About to be created"
      end
      
      sponsor = sponsor_for filename, doc, legislators, missing_ids
      cosponsors = cosponsors_for filename, doc, legislators, missing_ids
      actions = actions_for doc
      titles = titles_for doc
      state = doc.at(:state) ? doc.at(:state).inner_text : "UNKNOWN"
      votes = votes_for doc
      last_voted_at = votes.last ? votes.last[:voted_at] : nil
      introduced_at = Time.parse doc.at(:introduced)['datetime']
      
      bill.attributes = {
        :filename => filename,
        :type => type,
        :number => number,
        :code => code,
        :session => session,
        :chamber => {'h' => 'house', 's' => 'senate'}[type.first.downcase],
        :state => state,
        :short_title => most_recent_title_from(titles, :short),
        :official_title => most_recent_title_from(titles, :official),
        :titles => titles,
        :keywords => doc.search('//subjects/term').map {|term| term['name']},
        :summary => summary_for(doc),
        :sponsor => sponsor,
        :sponsor_id => sponsor ? sponsor[:bioguide_id] : nil,
        :cosponsors => cosponsors,
        :cosponsor_ids => cosponsors ? cosponsors.map {|c| c[:bioguide_id]} : nil,
        :cosponsors_count => cosponsors ? cosponsors.size : 0,
        :actions => actions,
        :last_action => actions.last,
        :last_action_at => actions.last ? actions.last[:acted_at] : nil,
        :votes => votes,
        :last_voted_at => last_voted_at,
        :introduced_at => introduced_at,
        :last_updated => Time.now
      }
      
      timeline = timeline_for doc, votes
      bill.attributes = timeline
      
      if bill.save
        count += 1
      else
        bad_bills << {:attributes => bill.attributes, :error_messages => bill.errors.full_messages}
      end
    end
    
    Report.success self, "Synced #{count} bills for session ##{session} from GovTrack.us.", {:elapsed_time => Time.now - start}
    
    if missing_ids.any?
      missing_ids = missing_ids.uniq
      Report.warning self, "Found #{missing_ids.size} missing GovTrack IDs, attached.", {:missing_ids => missing_ids}
    end
    
    if bad_bills.any?
      Report.failure self, "Failed to save #{bad_bills.size} bills. Attached the last failed bill's attributes and errors.", bad_bills.last
    end
    
    count
  rescue Exception => exception
    Report.failure self, "Exception while saving Bills. Attached exception to this message.", {:exception => {:backtrace => exception.backtrace, :message => exception.message}}
  end
  
  
  def self.summary_for(doc)
    summary = doc.at(:summary).inner_text.strip
    summary.present? ? summary : nil
  end
  
  def self.sponsor_for(filename, doc, legislators, missing_ids)
    sponsor = doc.at :sponsor
    sponsor and sponsor['id'] and !sponsor['withdrawn'] ? legislator_for(filename, sponsor['id'], legislators, missing_ids) : nil
  end
  
  def self.cosponsors_for(filename, doc, legislators, missing_ids)
    cosponsors = (doc/:cosponsor).map do |cosponsor| 
      cosponsor and cosponsor['id'] and !cosponsor['withdrawn'] ? legislator_for(filename, cosponsor['id'], legislators, missing_ids) : nil
    end.compact
    cosponsors.any? ? cosponsors : nil
  end
  
  def self.titles_for(doc)
    # important that the result be an array so that we preserve order of titles
    # to pick out the most recent title later
    titles = doc.search "//title"
    titles.map do |title|
      {
        :type => title['type'],
        :as => title['as'],
        :title => title.inner_text
      }
    end
  end
  
  # prepare the full timeline of a bill, lots-of-flags style
  def self.timeline_for(doc, votes)
    timeline = {}
    
    if house_vote = votes.select {|vote| vote[:chamber] == 'house' and vote[:type] != 'override'}.last
      timeline[:house_result] = house_vote[:result]
      timeline[:house_result_at] = house_vote[:voted_at]
    end
    
    if senate_vote = votes.select {|vote| vote[:chamber] == 'senate' and vote[:type] != 'override'}.last
      timeline[:senate_result] = senate_vote[:result]
      timeline[:senate_result_at] = senate_vote[:voted_at]
    end
    
    if concurring_vote = votes.select {|vote| vote[:type] == 'vote2'}.last
      timeline[:passed] = concurring_vote[:result] == 'pass'
      timeline[:passed_at] = concurring_vote[:voted_at]
    else
      timeline[:passed] = false
    end
    
    if vetoed_action = doc.at('//actions/vetoed')
      timeline[:vetoed_at] = Time.parse vetoed_action['datetime']
      timeline[:vetoed] = true
    else
      timeline[:vetoed] = false
    end
    
    if override_house_vote = votes.select {|vote| vote[:chamber] == 'house' and vote[:type] == 'override'}.last
      timeline[:override_house_result] = override_house_vote[:result]
      timeline[:override_house_result_at] = override_house_vote[:voted_at]
    end
    
    if override_senate_vote = votes.select {|vote| vote[:chamber] == 'senate' and vote[:type] == 'override'}.last
      timeline[:override_senate_result] = override_senate_vote[:result]
      timeline[:override_senate_result_at] = override_senate_vote[:voted_at]
    end
    
    if enacted_action = doc.at('//actions/enacted')
      timeline[:enacted_at] = Time.parse enacted_action['datetime']
      timeline[:enacted] = true
    else
      timeline[:enacted] = false
    end
    
    # finally, set the awaiting_signature flag, inferring it from the details above
    if timeline[:passed] and !timeline[:vetoed] and !timeline[:enacted] and topresident_action = doc.search('//actions/topresident').last
      timeline[:awaiting_signature_since] = Time.parse topresident_action['datetime']
      timeline[:awaiting_signature] = true
    else
      timeline[:awaiting_signature] = false
    end
    
    timeline
  end
  
  def self.most_recent_title_from(titles, type)
    groups = titles.select {|t| t[:type] == type.to_s}.group_by {|t| t[:as]}
    recent_group = groups[groups.keys.last]
    recent_group and recent_group.any? ? recent_group.first[:title] : nil
  end
  
  def self.actions_for(doc)
    doc.search('//actions/*').reject {|a| a.class == Hpricot::Text}.map do |action|
      {
        :acted_at => Time.parse(action['datetime']),
        :text => (action/:text).inner_text,
        :type => action.name
      }
    end
  end
  
  def self.votes_for(doc)
    chamber = {'h' => 'house', 's' => 'senate'}
    doc.search('//actions/vote|//actions/vote2|//actions/vote-aux').map do |vote|
      voted_at = Time.parse vote['datetime']
      chamber_code = vote['where']
      how = vote['how']
      
      result = {
        :how => how,
        :result => vote['result'], 
        :voted_at => voted_at,
        :text => (vote/:text).inner_text,
        :chamber => chamber[chamber_code],
        :type => vote['type']
      }
      
      if vote['roll'].present?
        result[:roll_id] = "#{chamber_code}#{vote['roll']}-#{voted_at.year}"
      end
      
      result
    end
  end
  
  
  def self.legislator_for(filename, govtrack_id, legislators, missing_ids)
    legislator = legislators[govtrack_id]
    
    if legislator
      attributes = legislator.attributes
      allowed_keys = sponsor_fields.map {|f| f.to_s}
      attributes.keys.each {|key| attributes.delete key unless allowed_keys.include?(key)}
      attributes
    else
      missing_ids << [govtrack_id, filename] if missing_ids
      nil
    end
  end
  
  # statistics functions
  
  def self.bills_sponsored_where(bioguide_id, options = {})
    count(:conditions => {:sponsor_id => bioguide_id}.merge(options))
  end
  
  def self.bills_cosponsored_where(bioguide_id, options = {})
    count(:conditions => {:cosponsor_ids => bioguide_id}.merge(options))
  end
  
  def self.format_time(time)
    time.strftime "%Y/%m/%d %H:%M:%S %z"
  end
  
  def self.current_session
    ((Time.now.year + 1) / 2) - 894
  end
  
  def self.type_for(type)
    {
      :h => 'hr',
      :hr => 'hres',
      :hj => 'hjres',
      :hc => 'hcres',
      :s => 's',
      :sr => 'sres',
      :sj => 'sjres',
      :sc => 'scres'
    }[type.to_sym]
  end
end