MSSQL = require './mssql'
Mangler = require './mangler'
Model = require 'provide-model'

class BaseModel extends MSSQL
  constructor: (Model, args...) ->
    super Model, args...
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


module.exports = new Model BaseModel
