class Mangler
  # convenient combination of DB resultsets (arrays of objects)

  constructor: (@parasite, @parasite_key, @as_collection=false) -> @

  as: (@as_key) =>
    return @_attach_collection_by_key @host, @host_key, @parasite, @parasite_key, @as_key, @include_keys if @as_collection
    @_attach_by_key @host, @host_key, @parasite, @parasite_key, @as_key, @include_keys

  pick: (@include_keys...) => @

  to: (@host, @host_key) => @

  _attach_by_key: (host, host_key, parasite, parasite_key, attach_as_key, include_keys=[]) ->
    # attach items from PARASITE array on corresponding item(s) of HOST array at key specified by ATTACH_AS_KEY
    throw new Error "attach_by_key: no HOST collection" unless host?
    throw new Error "attach_by_key: no PARASITE collection" unless parasite?
    p = new Map
    parasite.forEach (item) ->
      if include_keys.length > 0 # only include specified keys
        obj = {}
        for key in include_keys
          obj[key] = item[key]
        p.set item[parasite_key], obj
      else # include all PARASITE keys
        p.set item[parasite_key], item
    host.forEach (item) ->
      item[attach_as_key] = p.get item[host_key] if p.has item[host_key]
    host

  _attach_collection_by_key: (host, host_key, parasite, parasite_key, attach_as_key, include_keys=[]) ->
    # same as above but attach items as an array
    throw new Error "attach_collection_by_key: no HOST collection" unless host?
    throw new Error "attach_collection_by_key: no PARASITE collection" unless parasite?
    p = new Map
    parasite.forEach (item) ->
      p.set item[parasite_key], [] unless p.has item[parasite_key]
      if include_keys.length > 0 # only include specified keys
        obj = {}
        for key in include_keys
          obj[key] = item[key]
        arr = p.get item[parasite_key]
        arr.push obj
        p.set item[parasite_key], arr
      else # include all PARASITE keys
        arr = p.get(item[parasite_key])
        arr.push item
        p.set item[parasite_key], arr
    host.forEach (item) ->
      item[attach_as_key] = p.get item[host_key] if p.has item[host_key]
    host


module.exports = Mangler
