# provide-mssql

JSON model layer for Microsoft SQL Server (via Tedious) database in Express
apps.

BREAKING CHANGES in v0.3.0:

- `params` passed to a string-literal query should be passed as an explicit array
    instead of as individual arguments (see below)
- the (undocumented) `filter` functions are now expected to be an object
    rather than an array with a single (object) element.

## Installation

`npm i --save provide-mssql`

## Usage

Model (called from Express handler--for which consider [provide-handler](https://www.npmjs.com/package/provide-handler)):
```
model = require 'provide-mssql'

class TicketModel
  table: # DB table definition
    name: 'ticket' # table name in DB
    primary_key: '_id' # optional but important for INSERT/UPDATE queries
    schema: # whitelist of valid table columns (with datatypes)
      _id: 'Int'
      customer_id: 'VarChar'
      received_date: 'Date'
      hours: 'Decimal': precision: 4, scale: 2 # specify additional param options

  # and now the model methods....
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
      where: [
        ['@.customer_id', model.eq id]
      ]
    yield @request params


module.exports = model.provide TicketModel
```

Notice how we define a `primary_key` in the schema--this is to exclude that
column (`_id` in this example) from the fields affected by INSERT/UPDATE
queries, as we don't actually want to change that value.

Also note that model methods use "fat-arrow" to preserve context (so `this`
refers to the local class).

## Query Builder
```
select:
  table1: ['columnA', 'columnD']
  table2: ['columnA: othername', 'columnB', 'columnC']    

...becomes....

SELECT <base_table>.*, table1.columnA, table1.columnD, table2.columnA AS othername, table2.columnB, table2.columnC
```

A table name of `@` will be replaced with the model's `table.name` property (its
"base table").

An empty `select` object will default to `@.*` (all columns of model's base
table). Likewise if `select` is defined but doesn't include the base table.
Essentially, if you don't specify columns from the model base table, you're
getting `@.*`.

Defining a field as `COLUMN: ALIAS` will use the `AS` statement to assign an
alias to that column.

```
join: [
  ['@.other_id', 'othertable._id']
  ['RIGHT', 'othertable.third_id', 'thirdtable._id']
]

(FROM <base_table>)
LEFT JOIN othertable ON <base_table>.other_id = othertable._id
RIGHT JOIN thirdtable ON othertable.third_id = thirdtable._id
```

You can pass a `JOIN` direction as an optional first array element in a join
item; default is `LEFT`.

```
where: [
  ['@.some_id', model.eq 1234]
  ['table2.first_name', model.contains 'sephina']
]

WHERE <base_table>.some_id = 1234
AND table2.first_name LIKE '%sephina%'
```

```
where: [
  ['@.some_id', model.eq 1234]
  ['OR', 'table2.first_name', model.contains 'sephina']
]

WHERE <base_table>.some_id = 1234
OR table2.first_name LIKE '%sephina%'
```

You can pass 'OR' as an optional first array element in a where subclause;
default is `AND`.

```
WHERE clause comparators:
  contains: LIKE '%___%'
  ends_with: LIKE '%___'
  eq: =
  gt: >
  gte: >=
  in: IN (<array>)
  is_not_null: IS NOT NULL
  is_null: IS NULL
  lt: <
  lte: <=
  neq: <>
  starts_with: LIKE '___%'
```

See `test/mssql.coffee` for more query examples. If you run into a query that
won't build properly, just pass it as a string (with optional params):

```
method_with_challenging_query: (item_id, other_id) =>
  query = """SELECT *
    FROM table1
    LEFT JOIN table2 ON table1.field1 = table2.field1
      AND table1.field2 = table2.field2
    WHERE table1.id = @id
    AND table2.other_id = @other"""

  # version 0.3.x param syntax (see note below)
  yield @request query, [
    @build_param('id', 'Int', item_id),
    @build_param('other', 'Int', other_id)
  ]
```

NOTE: in versions < 0.3.x, `params` for string-literal queries should be passed
as individual arguments, not as an array.

## Transactions

You may pass an array of query objects to perform as a [transaction](http://tediousjs.github.io/tedious/api-connection.html#function_transaction):

```
q1 =
  update: { success: 1 }
  where: [
    ['id', model.eq item_id]
  ]
q2 =
  select: {}
  where: [
    ['@.item_id', model.eq item_id]
  ]
yield @transaction [{ name: 'some_query', query: q1 }, { name: 'another_query', query: q2 }]
```

...returned result in such a case would look like:

```
{
  some_query: [results of q1]
  another_query: [results of q2]
}
```

Query results will be "named" with the array index they are passed in with if no
`name` property is provided.

You may also pass string-literal queries like:

```
q1 = "SELECT * FROM items WHERE id = @id AND field2 = @other"
p1 = [@build_params('id', 'Int', item_id), @build_params('other', 'Int', other_id)]
yield @transaction [{ name: 'put', query: q1, params: p1 }, ...]
```

Note in that case that the `params` property for each query should be an array.

You can also perform transactions as a series of requests in your model:

```
tx = yield @start_transaction() # start transaction
yield @some_write_query tx

item = yield Item.get id, tx
unless item?
  return tx.done 'Couldn't get item' # roll back transaction

another_query =
  select: {}
  where: [
    ['@.item_id', model.eq item.id]
  ]
yield @request another_query, null, tx # pass explicit null PARAMS arg
tx.done() # commit transaction
```

Note that you must pass the transaction (the return value of
`start_transaction()`) to each request so the handler knows to use that rather
than acquiring a new `pool` connection. Neglecting to do this may cause the
request to hang, which is bad because transactions place a write-lock on the DB.
This means no other requests can be processed while the transaction is open!

It's also important not to forget calling `transaction.done()` when you're
finished (to commit), or `transaction.done(err)` (to roll back) if you're
handing errors in your model method (errors thrown in the `request` plumbing are
already handled this way).

## Testing

`npm test`
