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
