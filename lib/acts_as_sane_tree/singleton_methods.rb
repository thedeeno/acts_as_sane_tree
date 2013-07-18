module ActsAsSaneTree
  module SingletonMethods

    # Return all root nodes
    def roots
      configuration[:class].where(
        "#{configuration[:foreign_key]} IS NULL"
      ).order(configuration[:order])
    end

    # Return first root node
    def root
      configuration[:class].where("#{configuration[:foreign_key]} IS NULL").order(configuration[:order]).first
    end

    # src:: Array of nodes
    # chk:: Array of nodes
    # Return true if any nodes within chk are found within src
    def nodes_within?(src, chk)
      s = (src.is_a?(Array) ? src : [src]).map{|x|x.is_a?(ActiveRecord::Base) ? x.id : x.to_i}
      c = (chk.is_a?(Array) ? chk : [chk]).map{|x|x.is_a?(ActiveRecord::Base) ? x.id : x.to_i}
      if(s.empty? || c.empty?)
        false
      else
        q = configuration[:class].connection.select_all(
          "WITH RECURSIVE crumbs AS (
            SELECT #{configuration[:class].table_name}.*, 0 AS level FROM #{configuration[:class].table_name} WHERE id in (#{s.join(', ')})
            UNION ALL
            SELECT alias1.*, crumbs.level + 1 FROM crumbs JOIN #{configuration[:class].table_name} alias1 on alias1.parent_id = crumbs.id
          ) SELECT count(*) as count FROM crumbs WHERE id in (#{c.join(', ')})"
        )
        q.first['count'].to_i > 0
      end
    end

    # src:: Array of nodes
    # chk:: Array of nodes
    # Return all nodes that are within both chk and src
    def nodes_within(src, chk)
      s = (src.is_a?(Array) ? src : [src]).map{|x|x.is_a?(ActiveRecord::Base) ? x.id : x.to_i}
      c = (chk.is_a?(Array) ? chk : [chk]).map{|x|x.is_a?(ActiveRecord::Base) ? x.id : x.to_i}
      if(s.empty? || c.empty?)
        nil
      else
        query =
          "(WITH RECURSIVE crumbs AS (
            SELECT #{configuration[:class].table_name}.*, 0 AS depth FROM #{configuration[:class].table_name} WHERE id in (#{s.join(', ')})
            UNION ALL
            SELECT alias1.*, crumbs.depth + 1 FROM crumbs JOIN #{configuration[:class].table_name} alias1 on alias1.parent_id = crumbs.id
            #{configuration[:max_depth] ? "WHERE crumbs.depth + 1 < #{configuration[:max_depth].to_i}" : ''}
          ) SELECT * FROM crumbs WHERE id in (#{c.join(', ')})) as #{configuration[:class].table_name}"
        configuration[:class].from(query)
      end
    end

    # args:: ActiveRecord models or IDs - Symbols: :raw, :no_self - Hash: {:to_depth => n, :at_depth => n}
    # Returns provided nodes plus all descendants of provided nodes in nested Hash where keys are nodes and values are children
    # :raw:: return value will be flat array
    # :no_self:: Do not include provided nodes in result
    # Hash:
    #   :to_depth:: Only retrieve values to given depth
    #   :at_depth:: Only retrieve values from given depth
    def nodes_and_descendants(*args)
      raw = args.delete(:raw)
      no_self = args.delete(:no_self)
      at_depth = nil
      depth = nil
      hash = args.detect{|x|x.is_a?(Hash)}
      if(hash)
        args.delete(hash)
        depth = hash[:depth] || hash[:to_depth]
        at_depth = hash[:at_depth]
      end
      depth ||= configuration[:max_depth].to_i
      depth_restriction = "WHERE crumbs.depth + 1 < #{depth}" if depth
      depth_clause = nil
      if(at_depth)
        depth_clause = "#{configuration[:class].table_name}.depth + 1 = #{at_depth.to_i + 1}"
      elsif(depth)
        depth_clause = "#{configuration[:class].table_name}.depth + 1 < #{depth.to_i + 2}"
      end
      base_ids = args.map{|x| x.is_a?(ActiveRecord::Base) ? x.id : x.to_i}
      query =
        "(WITH RECURSIVE crumbs AS (
          SELECT #{configuration[:class].table_name}.*, #{no_self ? -1 : 0} AS depth FROM #{configuration[:class].table_name} WHERE #{base_ids.empty? ? 'parent_id IS NULL' : "id in (#{base_ids.join(', ')})"}
          UNION ALL
          SELECT alias1.*, crumbs.depth + 1 FROM crumbs JOIN #{configuration[:class].table_name} alias1 on alias1.parent_id = crumbs.id
          #{depth_restriction}
        ) SELECT * FROM crumbs) as #{configuration[:class].table_name}"
      q = nil

      q = configuration[:class].from(
        query
      ).where(
        "#{configuration[:class].table_name}.depth >= 0"
      )
      if(depth_clause)
        q = q.where(depth_clause)
      end
      if(configuration[:order].present?)
        q = q.order(configuration[:order])
      end
      unless(raw)
        res = ActiveSupport::OrderedHash.new
        cache = ActiveSupport::OrderedHash.new
        q.to_a.each do |item|
          res[item] = ActiveSupport::OrderedHash.new
          cache[item] = res[item]
        end
        cache.each_pair do |item, values|
          if(cache[item.parent])
            cache[item.parent][item] = values
            res.delete(item)
          end
        end
        res
      else
        q
      end
    end
    alias_method :nodes_and_descendents, :nodes_and_descendants

  end
end
