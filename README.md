# PgTest
Testing in PostgreSQL. Tested with PostgreSQL 9.4.

## Installation
Create database and execute `pgtest.sql`. This will create pgtest schema with functions that are used for testing.

```bash
curl --silent https://raw.githubusercontent.com/raitraidma/pgtest/master/pgtest.sql |\
sudo -u postgres psql mydatabasefortesting
```

To run PgTest's tests execute `pgtest_test.sql`. There you can also see how to use PgTest.

## Usage
Create schema for your tests:
```sql
CREATE SCHEMA IF NOT EXISTS test;
```

Create test functions. Test function MUST return `void` and start with `test_`. Tests are ordered by function name.
```sql
CREATE OR REPLACE FUNCTION test.test_a_equals_a_ok()
  RETURNS void AS
$$
BEGIN
  PERFORM pgtest.assert_equals('A', 'A');
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=test, pg_temp;
```
```sql
CREATE OR REPLACE FUNCTION test.test_a_equals_b_fails()
  RETURNS void AS
$$
BEGIN
  PERFORM pgtest.assert_equals('A', 'B');
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=test, pg_temp;
```

Run tests:
```sql
SELECT pgtest.run_tests('test');
-- OR
SELECT pgtest.run_tests(ARRAY['test_schema1','test_schema2']); -- Run tests from multiple schemas.
```

Result is number of messages that failed. Raised messages show more specific info about tests - what tests ran, how many failed, what was the cause and how long it took.
If you do not want to see pg_exception_context in messages then change `client_min_messages` to `NOTICE`. Otherwise use DEBUG, LOG or INFO.
```sql
SET client_min_messages TO NOTICE;
```

## Assertions
* `pgtest.assert_equals(expected_value, real_value [, custom_error_message]);`
* `pgtest.assert_not_equals(not_expected_value, real_value [, custom_error_message]);`
* `pgtest.assert_true(boolean_value [, custom_error_message]);`
* `pgtest.assert_false(boolean_value [, custom_error_message]);`
* `pgtest.assert_query_equals(expected_recordset, sql_query [, custom_error_message])`

`expected_value` and `real_value` must be same type (BIGINT, BIT, BOOLEAN, CHAR, VARCHAR, DOUBLE PRECISION, INT, REAL, SMALLINT, TEXT, TIME, TIMETZ, TIMESTAMP, TIMESTAMPTZ, XML or array).

`expected_recordset` is array TEXT[][] (e.g `ARRAY[ARRAY['a', 'b'], ARRAY['c', 'd']]`) and `sql_query` is sql query as text (e.g `'SELECT ''a'', ''b'''`).

## Mocking
* `pgtest.simple_mock(original_function_schema_name, original_function_name, function_arguments, mock_function_schema_name, mock_function_name)` - replaces original function with mock function. All parameters are `VARCHAR` type. `function_arguments` are function parameters separated by commas (just like usual function definition in Postgres).
* `pgtest.mock(original_function_schema_name, original_function_name, s_function_argument_types, mock_function_schema_name, mock_function_name)`. All parameters but `s_function_argument_types` are `VARCHAR` type. `s_function_argument_types` is array of `VARCHAR`. Values in `s_function_argument_types` must match with values in column `data_type` in table `information_schema.parameters`. This function returns mock_id (`VARCHAR`) that can be used to assert mock function calls.
* `pgtest.assert_mock_called(mock_id [, expected_times_called [, custom_error_message]])` - `mock_id` is value returned by `pgtest.mock` function. `expected_times_called` tells how many times we expect the mock function to be called (by default 1).
* `pgtest.assert_mock_called_with_arguments(mock_id, expected_arguments, call_time [, custom_error_message])` - `mock_id` is value returned by `pgtest.mock` function. `expected_arguments` tells what are the expected arguments (e.g `ARRAY['a', '1']`). `call_time` tells against which function call is tested.

## Alternatives
* [PGUnit 1](http://en.dklab.ru/lib/dklab_pgunit/)
* [PGUnit 2](https://github.com/adrianandrei-ca/pgunit)
* [plpgunit](https://github.com/mixerp/plpgunit)
* [pgTAP](https://github.com/theory/pgtap)
* [Dis](https://github.com/Imperium/Dis)