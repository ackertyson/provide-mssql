MSSQL = require './mssql'

class Mangler
  # convenient combination of DB resultsets (arrays of objects)

  constructor: (@parasite, @parasite_key) -> @

  as: (@as_key) =>
    @_attach_by_key @host, @host_key, @parasite, @parasite_key, @as_key, @include_keys

  pick: (@include_keys...) => @

  to: (@host, @host_key) => @

  _attach_by_key: (host, host_key, parasite, parasite_key, attach_as_key, include_keys=[]) ->
    # attach items from PARASITE array on corresponding item(s) of HOST array at key specified by ATTACH_AS_KEY
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
    # collect attached items in array(s)
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


class BaseModel extends MSSQL
  constructor: (name, schema) ->
    super name, schema
    Promise::parallel = @promise_all_from_obj
    @_stack = {}


  attach: (collection, key) ->
    new Mangler collection, key


  list_from_key: (data, extract_columns...) ->
    # return array of specified column(s) from provided resultset (which is an array of objects)
    if data? and data.length
      arr = []
      for item in data
        for column, i in extract_columns
          arr[i] ?= []
          arr[i].push item[column] unless item[column] in arr[i]
      if arr.length is 0
        []
      else if arr.length is 1
        arr[0]
      else
        arr
    else
      []


  promise_all_from_obj: (p_obj) ->
    # Process multiple independent requests asynchronously; think of this as
    #  the Promise version of 'async.parallel'
    ks = []
    vs = []
    for own k, v of p_obj
      # arrays will preserve relative order of key/value inputs...
      ks.push k
      vs.push v
    Promise.all(vs).then (results) -> # ...even in Promise results
      ret_val = {}
      results.forEach (value, index) ->
        # build obj out of corresponding input keys and result values
        ret_val[ks[index]] = value
      Promise.resolve ret_val
    .catch (err) ->
      Promise.reject err


  quoted_list: (arr) -> # for use in 'WHERE IN (...)' clause with VarChar values
    if arr? and arr.length > 0
      arr.map((x) -> "'"+x.toString()+"'").join(',')
    else
      return ''


class ModelProvider
  # Wrap model methods in ES6 generator function so we can use 'yield' instead
  #  of clunkier Promise.then().catch() (though all methods remain Promise-based
  #  under the hood); also add BaseModel properties to wrapped model. We do it
  #  this way because using 'CLASS ___ EXTENDS ___' breaks our Model prototype chain.

  # WHERE clause operators
  @contains: (value) -> ['LIKE ', '%'+value+'%']
  @ends_with: (value) -> ['LIKE ', '%'+value]
  @eq: (value) -> ['=', value]
  @gt: (value) -> ['>', value]
  @gte: (value) -> ['>=', value]
  @in: (values) ->
    values = [values] unless Array.isArray values
    #TODO sanitize values
    ['IN', "(#{values.join ','})"]
  @lt: (value) -> ['<', value]
  @lte: (value) -> ['<=', value]
  @starts_with: (value) -> ['LIKE ', value+'%']

  @provide: (Model, table_name) ->
    m = new Model
    base = new BaseModel table_name, m.schema
    m = @_wrap m # wrap MODEL methods in ES6 generator
    for name, method of base # add BaseModel instance properties (including methods) to MODEL...
      m[name] = method unless m[name]? # ...unless MODEL already has property of that name
    m

  @_typeof: (subject, type) ->
    # typeof that actually works!
    Object::toString.call(subject).toLowerCase().slice(8, -1) is type.toLowerCase()

  @_wrap: (obj) ->
    for name, prop of obj
      obj[name] = @_yields prop if @_typeof prop, 'function'
      if @_typeof prop, 'object'
        obj[name] = prop
        @_wrap prop
    obj

  @_yields: (callback) ->
    (args...) ->
      generator = callback.call null, args...
      handle = (result) ->
        return Promise.resolve result.value if result.done
        Promise.resolve(result.value).then (data) ->
          handle generator.next data
        , (err) ->
          handle generator.throw err
      try # initialize CALLBACK to first 'yield' call
        handle generator.next()
      catch ex
        Promise.reject ex


module.exports = ModelProvider
