#mssql-model

JSON model layer for Microsoft SQL Server (via Tedious) database in Express
apps.

##Installation

`npm i --save mssql-model`

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
    primary_key: '_id' # exclude PK from body of INSERT/UPDATE queries (see below)
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

# set DB table name to 'ticket' for this model...
module.exports = Model.provide TicketModel, 'ticket'
```

Notice how we define a `primary_key` in the schema--this is to exclude that
column (`_id` in this example) from the fields affected by INSERT/UPDATE
queries, as we don't actually want to change that value.

See `test/mssql.coffee` for more query examples.

##Testing

`npm test`