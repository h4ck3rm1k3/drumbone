#!/usr/bin/env ruby

require 'test/unit'

require 'rubygems'
require 'environment'

class BillTest < Test::Unit::TestCase
  
  def test_title_extraction
    cases = {
      'hr1-stimulus' => {
         :short => "American Recovery and Reinvestment Act of 2009",
         :official => "Making supplemental appropriations for job preservation and creation, infrastructure investment, energy efficiency and science, assistance to the unemployed, and State and local fiscal stabilization, for fiscal year ending September 30, 2009, and for other purposes."
      },
      'hr3590-health-care' => {
         :short => "Patient Protection and Affordable Care Act",
         :official => "An act entitled The Patient Protection and Affordable Care Act."
      },
      'hr4173-wall-street' => {
         :short => "Wall Street Reform and Consumer Protection Act of 2009",
         :official => "To provide for financial regulatory reform, to protect consumers and investors, to enhance Federal understanding of insurance issues, to regulate the over-the-counter derivatives markets, and for other purposes."
      },
      'no-short' => {
         :short => nil,
         :official => "An act entitled The Patient Protection and Affordable Care Act."
      }
    }
    
    cases.each do |filename, recents|
      doc = Hpricot.XML open("test/fixtures/titles/#{filename}.xml")
      titles = Bill.titles_for doc
      assert_equal recents[:short], Bill.most_recent_title_from(titles, :short)
      assert_equal recents[:official], Bill.most_recent_title_from(titles, :official)
    end
  end
  
  def test_timeline_construction
    cases = {
      :introduced => {
        :house_result => :missing,
        :house_result_at => :missing, 
        :senate_result => :missing,
        :senate_result_at => :missing, 
        :passed => false,
        :passed_at => :missing,  
        :enacted => false,
        :enacted_at => :missing,  
        :vetoed => false,
        :vetoed_at => :missing,
        :override_house_result => :missing,
        :override_house_result_at => :missing, 
        :override_senate_result => :missing, 
        :override_senate_result_at => :missing,
        :awaiting_signature => false,
        :awaiting_signature_since => :missing
      },
      :enacted_normal => {
        :house_result => 'pass',
        :house_result_at => :not_null, 
        :senate_result => 'pass',
        :senate_result_at => :not_null, 
        :passed => true,
        :passed_at => :not_null,  
        :enacted => true,
        :enacted_at => :not_null,
        :vetoed => false,
        :vetoed_at => :missing,
        :override_house_result => :missing,
        :override_house_result_at => :missing, 
        :override_senate_result => :missing, 
        :override_senate_result_at => :missing,
        :awaiting_signature => false,
        :awaiting_signature_since => :missing
      },
      :veto_override_failed => {
        :house_result => 'pass',
        :house_result_at => :not_null, 
        :senate_result => 'pass',
        :senate_result_at => :not_null, 
        :passed => true,
        :passed_at => :not_null,  
        :enacted => false,
        :enacted_at => :missing,
        :vetoed => true,
        :vetoed_at => :not_null,
        :override_house_result => 'fail',
        :override_house_result_at => :not_null, 
        :override_senate_result => :missing, 
        :override_senate_result_at => :missing,
        :awaiting_signature => false,
        :awaiting_signature_since => :missing
      },
      :veto_override_passed => {
        :house_result => 'pass',
        :house_result_at => :not_null, 
        :senate_result => 'pass',
        :senate_result_at => :not_null, 
        :passed => true,
        :passed_at => :not_null,  
        :enacted => true,
        :enacted_at => :not_null,
        :vetoed => true,
        :vetoed_at => :not_null,
        :override_house_result => 'pass',
        :override_house_result_at => :not_null, 
        :override_senate_result => 'pass', 
        :override_senate_result_at => :not_null,
        :awaiting_signature => false,
        :awaiting_signature_since => :missing
      },
      :passed_house_only => {
        :house_result => 'pass',
        :house_result_at => :not_null, 
        :senate_result => :missing,
        :senate_result_at => :missing, 
        :passed => false,
        :passed_at => :missing,  
        :enacted => false,
        :enacted_at => :missing,
        :vetoed => false,
        :vetoed_at => :missing,
        :override_house_result => :missing,
        :override_house_result_at => :missing, 
        :override_senate_result => :missing, 
        :override_senate_result_at => :missing,
        :awaiting_signature => false,
        :awaiting_signature_since => :missing
      },
      :enacted_but_one_vote => {
        :house_result => :missing,
        :house_result_at => :missing, 
        :senate_result => 'pass',
        :senate_result_at => :not_null, 
        :passed => true,
        :passed_at => :not_null,  
        :enacted => true,
        :enacted_at => :not_null,
        :vetoed => false,
        :vetoed_at => :missing,
        :override_house_result => :missing,
        :override_house_result_at => :missing, 
        :override_senate_result => :missing, 
        :override_senate_result_at => :missing,
        :awaiting_signature => false,
        :awaiting_signature_since => :missing
      },
      :passed_awaiting_signature => {
        :house_result => 'pass',
        :house_result_at => :not_null, 
        :senate_result => 'pass',
        :senate_result_at => :not_null, 
        :passed => true,
        :passed_at => :not_null,  
        :enacted => false,
        :enacted_at => :missing,
        :vetoed => false,
        :vetoed_at => :missing,
        :override_house_result => :missing,
        :override_house_result_at => :missing, 
        :override_senate_result => :missing, 
        :override_senate_result_at => :missing,
        :awaiting_signature => true,
        :awaiting_signature_since => :not_null
      },
      :passed_awaiting_conference => {
        :house_result => 'pass',
        :house_result_at => :not_null, 
        :senate_result => 'pass',
        :senate_result_at => :not_null, 
        :passed => false,
        :passed_at => :missing,
        :enacted => false,
        :enacted_at => :missing,
        :vetoed => false,
        :vetoed_at => :missing,
        :override_house_result => :missing,
        :override_house_result_at => :missing, 
        :override_senate_result => :missing, 
        :override_senate_result_at => :missing,
        :awaiting_signature => false,
        :awaiting_signature_since => :missing
      }
    }
    
    cases.keys.each do |name|
      doc = Hpricot.XML open("test/fixtures/timeline/#{name}.xml")
      state = Bill.state_for doc
      votes = Bill.votes_for doc
      timeline = Bill.timeline_for doc, state, votes
      
      cases[name].each do |key, value|
        if value == :missing
          assert !timeline.key?(key), "[#{name}] #{key}: #{value}"
        elsif value == :not_null
          assert_not_nil timeline[key], "[#{name}] #{key}: #{value}"
        else
          assert_equal value, timeline[key], "[#{name}] #{key}: #{value}"
        end
      end
    end
    
  end
  
end