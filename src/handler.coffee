class HandlerProvider
  # centralize all Express handler response logic by wrapping handler methods in
  #  helper function; note that these are static (not instance) methods...
  
  @provide: (Handler, name, schema) ->
    h = new Handler
    @_wrap h

  @_typeof: (subject, type) ->
    # typeof that actually works!
    Object::toString.call(subject).toLowerCase().slice(8, -1) is type

  @_wrap: (obj) ->
    for name, prop of obj
      obj[name] = @_wrapper prop if @_typeof prop, 'function'
      if @_typeof prop, 'object'
        obj[name] = prop
        @_wrap prop
    obj

  @_wrapper: (callback) ->
    # pass REQ to CALLBACK (which is the handler method) but handle all response
    #  logic here so the handlers don't have to worry about it
    (req, res, next) ->
      callback(req).then (data) ->
        res.status(200).json data
      .catch (err) ->
        res.status(500).json err


module.exports = HandlerProvider
