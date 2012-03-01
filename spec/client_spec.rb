require 'spec_helper'

describe Haplocheirus::Client do

  ARBITRARILY_LARGE_LIMIT = 100
  PREFIX = 'timeline:'

  TWEET_1   = "\001\000\000\000\000\000\000\000\001\000\000\000\000\000\000\000\000\000\000\000"
  RETWEET_1 = "\002\000\000\000\000\000\000\000\001\000\000\000\000\000\000\000\000\000\000\200"
  TWEET_3   = "\003\000\000\000\000\000\000\000\003\000\000\000\000\000\000\000\000\000\000\000"
  RETWEET_3 = "\004\000\000\000\000\000\000\000\003\000\000\000\000\000\000\000\000\000\000\200"
  DUPE_1    = "\005\000\000\000\000\000\000\000\001\000\000\000\000\000\000\000\000\000\000\200"
  DUPE_3    = "\006\000\000\000\000\000\000\000\003\000\000\000\000\000\000\000\000\000\000\200"
  TWEET_7   = "\007\000\000\000\000\000\000\000\007\000\000\000\000\000\000\000\000\000\000\000"
  
  before(:each) do
    @client  = Haplocheirus::Client.new(Haplocheirus::MockService.new)

    # Use the constructor below to run the test against a local haplo server
    # @client = Haplocheirus.new
  end

  describe 'append' do
    it 'works' do
      @client.store PREFIX + '0', [RETWEET_1]
      @client.append TWEET_3, PREFIX, [0]

      rval = @client.get(PREFIX + '0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == [TWEET_3, RETWEET_1]
      rval.size.should == 2
      rval.should be_hit
    end

    it 'supports single timeline ids' do
      @client.store PREFIX + '0', [RETWEET_1]
      @client.append TWEET_3, PREFIX, 0

      rval = @client.get(PREFIX + '0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == [TWEET_3, RETWEET_1]
      rval.size.should == 2
      rval.should be_hit
    end
  end

  describe 'remove' do
    it 'works' do
      @client.store PREFIX + '0', [TWEET_3]
      @client.remove TWEET_3, PREFIX, [0]
      @client.get(PREFIX + '0', 0, ARBITRARILY_LARGE_LIMIT).size.should == 0
    end
  end

  describe 'get' do
    it 'works' do
      vals = (1..20).map { |i| ([i]*2).pack("Q*") }
      @client.store '0', vals
      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == vals.reverse
      rval.size.should == 20
      rval.should be_hit
    end

    it 'does not dedupe by default' do
      timeline = [RETWEET_3,TWEET_3, RETWEET_1] 
      @client.store '0', timeline
      @client.get('0', 0, ARBITRARILY_LARGE_LIMIT).entries.should == timeline
    end

    it 'dedupes with source present' do
      timeline = [RETWEET_3,TWEET_3, RETWEET_1]
      @client.store '0', timeline
      @client.get('0', 0, ARBITRARILY_LARGE_LIMIT, true).entries.should == timeline[1,2]
    end

    it 'dedupes without source present' do
      timeline = [DUPE_1, DUPE_3, RETWEET_3, RETWEET_1]
      @client.store '0', timeline
      @client.get('0', 0, ARBITRARILY_LARGE_LIMIT, true).entries.should == timeline[2,3]
    end

    it 'sorts by recency' do
      reversed_timeline = [RETWEET_1,TWEET_3, RETWEET_3]
      @client.store '0', reversed_timeline
      @client.get('0', 0, ARBITRARILY_LARGE_LIMIT, true).entries.should == reversed_timeline[0,2].reverse
    end
    
    it 'returns nil on error' do
      @client.delete '0'
      @client.get('0', 0, ARBITRARILY_LARGE_LIMIT).should be_nil
    end

    it 'returns an empty set' do
      @client.store '0', []
      @client.get('0', 0, ARBITRARILY_LARGE_LIMIT).entries.should == []
    end
  end

  describe 'get_multi' do
    it 'returns multiple timelines' do
      @client.store '0', [TWEET_1]
      @client.store '1', [TWEET_3]
      @client.store '2', [TWEET_7]

      # blech
      query = ['0', '1', '2'].map do |i|
        Haplocheirus::TimelineGet.new(:timeline_id => i,
                                      :offset => 0,
                                      :length => 10)
      end
      
      rval = @client.get_multi(query)
      # Strict ordering, here...
      rval[0].entries.should == [TWEET_1]
      rval[1].entries.should == [TWEET_3]
      rval[2].entries.should == [TWEET_7]
    end

    it 'returns an empty segment on miss' do
      @client.store '0', [TWEET_1]
      @client.delete '1'

      # blech
      query = ['0', '1'].map do |i|
        Haplocheirus::TimelineGet.new(:timeline_id => i,
                                      :offset => 0,
                                      :length => 10)
      end

      rval = @client.get_multi(query)
      rval[0].entries.should == [TWEET_1]
      rval[0].should be_hit

      rval[1].entries.should == []
      rval[1].should be_miss
    end
  end
  
  describe 'range' do
    it 'returns with a lower bound' do
      @client.store '0', (1..20).map { |i| [i].pack("Q") }.reverse
      rval = @client.range('0', 5)
      rval.entries.should == 20.downto(6).map { |i| [i].pack("Q") }
      rval.size.should == 15
      rval.should be_hit
    end

    it 'returns with an upper bound' do
      @client.store '0', (1..20).map { |i| [i].pack("Q") }.reverse
      rval = @client.range('0', 5, 10)
      rval.entries.should == 9.downto(6).map { |i| [i].pack("Q") }
      rval.size.should == 4
      rval.should be_hit
    end

    it 'does not dedupe by default' do
      timeline = [RETWEET_3,TWEET_3, RETWEET_1]
      @client.store '0', timeline
      @client.range('0', 0, 10).entries.should == timeline
    end

    it 'dedupes with source present' do
      timeline = [RETWEET_3,TWEET_3, RETWEET_1]
      @client.store '0', timeline
      @client.range('0', 0, 10, true).entries.should == timeline[1,2]
    end

    it 'dedupes without source present' do
      timeline = [DUPE_1, DUPE_3, RETWEET_3, RETWEET_1]
      @client.store '0', timeline
      @client.range('0', 0, 10, true).entries.should == timeline[2,3]
    end

    it 'slices before deduping' do
      # todo?
    end

    it 'returns nil on error' do
      @client.delete '0'
      @client.range('0', 5).should be_nil
    end

    it 'returns an empty set' do
      @client.store '0', []
      @client.range('0', 5).entries.should == []
    end
  end

  describe 'store' do
    it 'works' do
      @client.store '0', ['foo']
      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == ['foo']
      rval.size.should == 1
      rval.should be_hit
    end
  end

  describe 'filter' do
    it 'works' do
      @client.store '0', [TWEET_3, TWEET_1]
      @client.filter('0', TWEET_3).should == [TWEET_3]
      @client.filter('0', [TWEET_3]).should == [TWEET_3]
    end

    it 'returns [] on error' do
      @client.delete '0'
      @client.filter('0', TWEET_3).should == []
    end

    it 'returns an empty set' do
      @client.store '0', []
      @client.filter('0', TWEET_3).should == []
    end
  end

  describe 'merge' do
    it 'works' do
      @client.store '0', [TWEET_7, TWEET_1]
      @client.merge '0', [TWEET_3]

      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == [TWEET_7, TWEET_3, TWEET_1]
      rval.size.should == 3
      rval.should be_hit
    end
  end

  describe 'merge_indirect' do
    it 'works' do
      @client.store '0', [TWEET_7, TWEET_1]
      @client.store '1', [TWEET_3]
      @client.merge_indirect '0', '1'

      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == [TWEET_7, TWEET_3, TWEET_1]
      rval.size.should == 3
      rval.should be_hit
    end

    it 'no-ops for non-existing source' do
      @client.store '0', ['foo']
      @client.delete '1' # just in case
      @client.merge_indirect '0', '1'

      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == ['foo']
      rval.size.should == 1
      rval.should be_hit
    end
  end

  describe 'unmerge' do
    it 'works' do
      @client.store '0', [TWEET_7, TWEET_3, TWEET_1]
      @client.unmerge('0', [TWEET_3])

      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == [TWEET_7, TWEET_1]
      rval.size.should == 2
      rval.should be_hit
    end
  end

  describe 'unmerge_indirect' do
    it 'works' do
      @client.store '0', [TWEET_7, TWEET_3, TWEET_1]
      @client.store '1', [TWEET_3]
      @client.unmerge_indirect '0', '1'

      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == [TWEET_7, TWEET_1]
      rval.size.should == 2
      rval.should be_hit
    end

    it 'no-ops for non-existing source' do
      @client.store '0', ['foo']
      @client.delete '1' # just in case
      @client.unmerge_indirect '0', '1'

      rval = @client.get('0', 0, ARBITRARILY_LARGE_LIMIT)
      rval.entries.should == ['foo']
      rval.size.should == 1
      rval.should be_hit
    end
  end

  describe 'delete' do
    it 'works' do
      @client.store '0', ['foo']
      @client.delete '0'
      @client.get('0', 0, ARBITRARILY_LARGE_LIMIT).should be_nil
    end
  end

end
