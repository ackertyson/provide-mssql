MSSQL = require './mssql'
Mangler = require './mangler'

class BaseModel extends MSSQL
  constructor: (name, schema) ->
    super name, schema
    Promise::parallel = @promise_all_from_obj


  # these functions assume that FILTERS is an array which *may* contain an object as the sole element
  has_filter: (filters, key) -> filters[0]?[key] or false
  get_filter: (args...) -> @has_filter args...
  pop_filter: (filters, key) ->
    value = @has_filter filters, key
    delete filters[0][key] if value
    return value
  set_filter: (filters, key, value, safe=false) ->
    if filters[0]?
      filters[0][key] = value unless filters[0][key]? and safe
    else
      filters = [{ key: value }]


  attach: (collection, key) ->
    new Mangler collection, key


  list_of_key: (data, extract_columns...) ->
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
