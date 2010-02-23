#!/usr/bin/env ruby

require 'test/unit'

require 'rubygems'
require 'environment'

class RollTest < Test::Unit::TestCase
  
  def test_vote_breakdown_for_regular_vote
    voters = [
        {:voter => {'party' => 'R'}, :vote => '+'},
        {:voter => {'party' => 'R'}, :vote => '+'},
        {:voter => {'party' => 'R'}, :vote => '0'},
        {:voter => {'party' => 'D'}, :vote => '-'},
        {:voter => {'party' => 'D'}, :vote => '+'},
      ]
    breakdown = Roll.vote_breakdown_for voters
    totals = breakdown.delete :total
    
    assert_equal 1, totals[:not_voting]
    assert_equal 3, totals[:ayes]
    assert_equal 1, totals[:nays]
    assert_not_nil totals[:present]
    assert_equal 0, totals[:present]
    
    assert_equal 2, breakdown['R'][:ayes]
    assert_equal 1, breakdown['R'][:not_voting]
    assert_not_nil breakdown['R'][:present]
    assert_equal 0, breakdown['R'][:present]
    assert_not_nil breakdown['R'][:nays]
    assert_equal 0, breakdown['R'][:nays]
    
    assert_equal 1, breakdown['D'][:ayes]
    assert_equal 1, breakdown['D'][:nays]
    assert_not_nil breakdown['D'][:present]
    assert_equal 0, breakdown['D'][:present]
    assert_not_nil breakdown['D'][:not_voting]
    assert_equal 0, breakdown['D'][:not_voting]
  end
  
  def test_vote_breakdown_for_speaker_election
    voters = [
        {:voter => {'party' => 'R'}, :vote => 'Boehner'},
        {:voter => {'party' => 'R'}, :vote => 'Boehner'},
        {:voter => {'party' => 'R'}, :vote => 'Pelosi'},
        {:voter => {'party' => 'D'}, :vote => 'Pelosi'},
        {:voter => {'party' => 'D'}, :vote => 'Pelosi'},
      ]
    
    breakdown = Roll.vote_breakdown_for voters
    totals = breakdown.delete :total
    
    assert_equal 3, totals['Pelosi']
    assert_equal 2, totals['Boehner']
    [:ayes, :nays, :not_voting, :present].each do |vote|
      assert_not_nil totals[vote]
      assert_equal 0, totals[vote]
    end
    
    assert_equal 2, breakdown['D']['Pelosi']
    assert_not_nil breakdown['D']['Boehner']
    assert_equal 0, breakdown['D']['Boehner']
    assert_equal 2, breakdown['R']['Boehner']
    assert_equal 1, breakdown['R']['Pelosi']
    
    [:ayes, :nays, :not_voting, :present].each do |vote|
      assert_not_nil breakdown['D'][vote]
      assert_equal 0, breakdown['D'][vote]
      assert_not_nil breakdown['R'][vote]
      assert_equal 0, breakdown['R'][vote]
    end
  end
  
end