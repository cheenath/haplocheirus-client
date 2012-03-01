require 'set'

class Haplocheirus::MockService #:nodoc:

  class MockNode < Struct.new(:status_id, :secondary_id, :bitfield)
    include Comparable

    RETWEET_BIT = 31

    def self.unpack(string)
      new *string.unpack("QQI")
    end

    def initialize(*args)
      super
      self.bitfield ||= 0
    end

    def <=>(other)
      status_id <=> other.status_id
    end

    def is_share?
      bitfield[RETWEET_BIT] == 1
    end
  end

  def initialize
    @timelines = {}
  end

  def append(e, p, is)
    is.each do |i|
      key = p + i.to_s
      next unless @timelines.key?(key)
      # NOTE: This check occurs on read, server-side
      @timelines[key].unshift(e) unless @timelines[key].include?(e)
    end
  end

  def remove(e, p, is)
    is.each do |i|
      key = p + i.to_s
      next unless @timelines.key?(key)
      @timelines[key].reject! { |i| i == e }
      # Haplo no longer delets an empty timeline from cache
      # @timelines.delete(key) if @timelines[key].empty?
    end
  end

  def get(i, o, l, d = false)
    raise Haplocheirus::TimelineStoreException unless @timelines.key?(i)
    t = @timelines[i].to_a[o..(o+l)]
    t.sort! { |a, b| a[0,8].unpack("Q") <=> b[0,8].unpack("Q") }
    t = dedupe(t) if d
    Haplocheirus::TimelineSegment.new(:entries => t.reverse.map{ |tt| tt.dup },
                                      :size => t.length,
                                      :state => Haplocheirus::TimelineSegmentState::HIT)
  end

  def get_multi(qs)
    qs.map do |q|
      begin
        get q.timeline_id, q.offset, q.length, q.dedupe
      rescue Haplocheirus::TimelineStoreException
        Haplocheirus::TimelineSegment.new(:entries => [],
                                          :size => 0,
                                          :state => Haplocheirus::TimelineSegmentState::MISS)
      end
    end
  end
  
  def get_range(i, f, t = 0, d = false)
    raise Haplocheirus::TimelineStoreException unless @timelines.key?(i)
    min = @timelines[i].index([f].pack("Q"))
    max = t > 0 ? @timelines[i].index([t].pack("Q")) : 0
    max = (max && max != 0) ? max+1 : 0
    t = min ? @timelines[i][max..min-1] : @timelines[i]
    t.sort! { |a, b| a[0,8].unpack("Q") <=> b[0,8].unpack("Q") }
    t = dedupe(t) if d
    Haplocheirus::TimelineSegment.new(:entries => t.reverse,
                                      :size => t.length,
                                      :state => Haplocheirus::TimelineSegmentState::HIT)
  end

  def store(i, e)
    @timelines[i] = []
    e.reverse.each { |n| append n, '', [i] }
  end

  def filter(i, e, depth = -1)
    raise Haplocheirus::TimelineStoreException unless @timelines.key?(i)

    haystack = @timelines[i].map do |ea|
      node = MockNode.unpack(ea)
      if node.is_share?
        node.secondary_id
      else
        node.status_id
      end
    end.uniq

    # FIXME: Only send the first 8 bytes for the needles
    e.select do |packed|
      node = MockNode.unpack(packed)
      haystack.include?(node.status_id)
    end
  end

  def merge(i, e)
    return unless @timelines.key?(i)

    e.each do |el|
      o = 0
      o += 1 while @timelines[i][0] <= el
      @timelines[i].insert(o + 1, el)
    end
  end

  def merge_indirect(d, s)
    merge(d, @timelines[s]) if @timelines.key?(s)
  end

  def unmerge(i, e)
    return unless @timelines.key?(i)
    @timelines[i].reject! { |o| e.find { |el| MockNode.unpack(el) == MockNode.unpack(o) } }
  end

  def unmerge_indirect(d, s)
    unmerge(d, @timelines[s]) if @timelines.key?(s)
  end

  def delete_timeline(i)
    @timelines.delete(i)
  end

  # This is not part of Haplo, but is useful for test harnesses
  def reset!
    @timelines = {}
  end

  private

  def dedupe(t)
    # I can't wait until Array#uniq takes a block...
    seen = { }
    nodes = []

    t.each do |i|
      node = MockNode.unpack(i)
      next if seen.key?(node.status_id)
      
      if node.is_share?
        next if seen.key?(node.secondary_id)

        seen[node.status_id] = i
        seen[node.secondary_id] = true
        nodes << node.status_id
      else
        seen[node.status_id] = i
        nodes << node.status_id
      end
    end

    seen.values_at(*nodes.sort!)
  end

end
