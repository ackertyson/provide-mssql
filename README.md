#mssql-model

JSON model layer for MSSQL/Tedious database in Express apps.

##Usage

Handler (called by Express route):
```
{ Handler } = require 'mssql-model'
Ticket = require '../models/ticket'

class TicketHandler
  # req, res, next are passed from Express; here we're dereferencing BODY from
  # req because it's all we need...
  get: ({ body }) ->
    Ticket.all body._filters

  # ...and here we only need req.params....
  for_customer: ({ params }) ->
    Ticket.find_by_customer params.customer_id

module.exports = Handler.provide TicketHandler
```

Model (called from handler):
```
{ Model } = require 'mssql-model'

class TicketModel
  # whitelist of valid DB table columns and their datatypes...
  schema:
    _id: 'Int'
    customer_id: 'VarChar'
    received_date: 'Date'

  all: (filters...) =>
    # JSON object will be built into SQL query...
    params =
      select:
        customer: ['name: customer_name', 'region']
      join: [
        ['@.customer_id', 'customer._id']
      ]
    yield @request params

  find_by_customer: (id) =>
    params =
      select: {}
      join: [
        ['@.customer_id', 'customer._id']
      ]
      where:
        '@.customer_id': Model.eq id
    yield @request params

# set DB table name to TICKET for this model...
module.exports = Model.provide TicketModel, 'ticket'
```

Here's a more complex query example:
```
params =
  select:
    table1: ['column1']
  join: [
    ['table1._id', 'table2.vehicle_id']
  ]
  where:
    '@._id': Model.eq 1234
  order_by: ['column1']
```
...becomes....
```
SELECT table1.column1,test.*
FROM test,table1
  LEFT JOIN table2 ON table1._id = table2.vehicle_id
WHERE [test].[_id] = @id
ORDER BY column1
```
Notice how the model base table (as passed to Model.provide, in this case
`test`) is added to the `SELECT` clause by default.
