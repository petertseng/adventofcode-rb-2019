require_relative 'priority_queue'

module Search
  module_function

  def path_of(prevs, n)
    path = [n]
    current = n
    while (current = prevs[current])
      path.unshift(current)
    end
    path.freeze
  end

  def astar(start, neighbours:, heuristic:, goal:, verbose: false)
    g_score = Hash.new(1.0 / 0.0)
    g_score[start] = 0

    closed = {}
    open = MonotonePriorityQueue.new
    open[start] = heuristic[start]
    prev = {}

    while (current = open.pop)
      next if closed[current]
      closed[current] = true

      return [g_score[current], prev.freeze] if goal[current]

      neighbours[current].each { |neighbour, cost|
        next if closed[neighbour]
        tentative_g_score = g_score[current] + cost
        next if tentative_g_score >= g_score[neighbour]

        prev[neighbour] = current if verbose
        g_score[neighbour] = tentative_g_score
        open[neighbour] = tentative_g_score + heuristic[neighbour]
      }
    end

    nil
  end

  def bfs(start, num_goals: 1, neighbours:, goal:, verbose: false)
    current_gen = [start]
    prev = {start => nil}
    goals = {}
    gen = -1

    until current_gen.empty?
      gen += 1
      next_gen = []
      while (cand = current_gen.shift)
        if goal[cand]
          goals[cand] = gen
          if goals.size >= num_goals
            next_gen.clear
            break
          end
        end

        neighbours[cand].each { |neigh|
          next if prev.has_key?(neigh)
          prev[neigh] = cand
          next_gen << neigh
        }
      end
      current_gen = next_gen
    end

    {
      gen: gen,
      goals: goals.freeze,
      prev: prev.freeze,
    }.merge(verbose ? {paths: goals.to_h { |goal, _gen| [goal, path_of(prev, goal)] }.freeze} : {}).freeze
  end
end
