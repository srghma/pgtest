CREATE SCHEMA IF NOT EXISTS pgtest;

---------------
-- EXECUTION --
---------------
DROP SEQUENCE IF EXISTS pgtest.unique_id;
CREATE SEQUENCE pgtest.unique_id CYCLE;


DROP AGGREGATE IF EXISTS pgtest.array_agg_mult (ANYARRAY);


CREATE AGGREGATE pgtest.array_agg_mult (ANYARRAY)  (
  SFUNC    = array_cat
, STYPE    = anyarray
, INITCOND = '{}'
);


CREATE OR REPLACE FUNCTION pgtest.f_get_test_functions_in_schema(s_schema_name VARCHAR)
  RETURNS TABLE (
    function_name VARCHAR
  ) AS
$$
  SELECT routine_name
  FROM information_schema.routines
  WHERE routine_schema = s_schema_name
    AND routine_type = 'FUNCTION'
    AND data_type = 'void'
    AND routine_name LIKE 'test_%'
  ORDER BY routine_name ASC;
$$ LANGUAGE sql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.f_create_error_message(s_returned_sqlstate TEXT, s_message_text TEXT, s_pg_exception_context TEXT)
  RETURNS varchar AS
$$
DECLARE
  s_logging_level VARCHAR;
  s_error_message VARCHAR;
BEGIN
  SHOW client_min_messages INTO s_logging_level;
  s_error_message := 'ERROR' || coalesce(' (' || s_returned_sqlstate || ')', '') || ': ' || coalesce(s_message_text, '');

  IF (upper(s_logging_level) IN ('DEBUG', 'LOG', 'INFO')) THEN
    s_error_message := s_error_message || E'\n' || coalesce(s_pg_exception_context, '');
  END IF;

  RETURN s_error_message;
END;
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.f_json_object_values_to_array(j_json_object JSON)
  RETURNS TEXT[] AS
$$
  SELECT array_agg(j.value) FROM (SELECT (json_each_text(j_json_object)).value) j;
$$ LANGUAGE sql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.f_run_test(s_schema_name VARCHAR, s_function_name VARCHAR)
  RETURNS varchar AS
$$
DECLARE
  s_returned_sqlstate    TEXT;
  s_message_text         TEXT;
  s_pg_exception_context TEXT;
BEGIN
  EXECUTE 'SELECT ' || s_schema_name || '.' || s_function_name || '();';
  RAISE 'OK' USING ERRCODE = '40004';
EXCEPTION
  WHEN SQLSTATE '40004' THEN
    RETURN 'OK';
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS s_returned_sqlstate = RETURNED_SQLSTATE,
                            s_message_text = MESSAGE_TEXT,
                            s_pg_exception_context = PG_EXCEPTION_CONTEXT;
    RETURN f_create_error_message(s_returned_sqlstate, s_message_text, s_pg_exception_context);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.f_get_function_description(s_schema_name VARCHAR, s_function_name VARCHAR, s_function_argument_types VARCHAR[])
  RETURNS json AS
$$
  SELECT row_to_json(fp) FROM (
    SELECT
      f.routine_schema
    , f.routine_name
    , f.routine_data_type
    , f.security_type
    , array_agg(f.parameter_mode) AS parameter_modes
    , array_agg(f.parameter_name) AS parameter_names
    , array_agg(f.parameter_data_type) AS parameter_data_types
    , array_agg(f.parameter_default) AS parameter_defaults
    FROM (
      SELECT
        r.specific_catalog
      , r.specific_schema
      , r.specific_name
      , r.routine_schema
      , r.routine_name
      , r.data_type AS routine_data_type
      , r.security_type
      , p.parameter_mode::VARCHAR
      , p.parameter_name::VARCHAR
      , p.data_type::VARCHAR AS parameter_data_type
      , p.parameter_default::VARCHAR
      FROM information_schema.routines r
      LEFT JOIN information_schema.parameters p ON (r.specific_catalog = p.specific_catalog AND r.specific_schema = p.specific_schema AND r.specific_name = p.specific_name)
      WHERE r.routine_schema = s_schema_name
        AND r.routine_name = s_function_name
        AND r.routine_type = 'FUNCTION'
      ORDER BY p.ordinal_position ASC
    ) f
    GROUP BY
      f.specific_catalog
    , f.specific_schema
    , f.specific_name
    , f.routine_schema
    , f.routine_name
    , f.routine_data_type
    , f.security_type
  ) fp WHERE fp.parameter_data_types = (CASE
    WHEN array_length(s_function_argument_types, 1) IS NULL THEN ARRAY[NULL]::VARCHAR[]
    ELSE s_function_argument_types
  END);
$$ LANGUAGE sql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.f_get_function_parameters(j_original_function_description JSON)
  RETURNS varchar AS
$$
DECLARE
  s_parameters VARCHAR := '';
  s_parameter_modes VARCHAR[];
  s_parameter_names VARCHAR[];
  s_parameter_data_types VARCHAR[];
  s_parameter_defaults VARCHAR[];
  i_position INT;
BEGIN
    SELECT
    array_agg(f2.parameter_mode) AS parameter_modes
  , array_agg(f2.parameter_name) AS parameter_names
  , array_agg(f2.parameter_data_type) AS parameter_data_types
  , array_agg(f2.parameter_default) AS parameter_defaults
  INTO
    s_parameter_modes, s_parameter_names, s_parameter_data_types, s_parameter_defaults
  FROM (
    SELECT
      json_array_elements_text(j_original_function_description->'parameter_modes') AS parameter_mode
    , json_array_elements_text(j_original_function_description->'parameter_names') AS parameter_name
    , json_array_elements_text(j_original_function_description->'parameter_data_types') AS parameter_data_type
    , json_array_elements_text(j_original_function_description->'parameter_defaults') AS parameter_default
  ) f2;

  IF (s_parameter_data_types[1] IS NULL) THEN
    RETURN '';
  END IF;

  FOR i_position IN 1 .. array_length(s_parameter_data_types, 1) LOOP
    IF (i_position > 1) THEN
      s_parameters := s_parameters || ', ';
    END IF;
    s_parameters := s_parameters || coalesce(s_parameter_modes[i_position], '') || ' '
                                 || coalesce(s_parameter_names[i_position], '') || ' '
                                 || coalesce(s_parameter_data_types[i_position], '') || ' '
                                 || coalesce(' DEFAULT ' || s_parameter_defaults[i_position], '');
  END LOOP;

  RETURN s_parameters;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.f_create_mock_function(s_mock_id VARCHAR, j_original_function_description JSON, s_mock_function_schema_name VARCHAR, s_mock_function_name VARCHAR)
  RETURNS void AS
$$
DECLARE
  s_call_method VARCHAR := 'RETURN';
BEGIN
  IF ((j_original_function_description->>'routine_data_type') = 'void') THEN
    s_call_method := 'PERFORM';
  END IF;

  EXECUTE format('CREATE FUNCTION %1$s.%2$s(%3$s)
                    RETURNS %4$s AS
                  $MOCK$
                  DECLARE
                    s_mock_id VARCHAR := ''%5$s'';
                    s_arguments JSON;
                  BEGIN
                    s_arguments := to_json(ARRAY[%9$s]::TEXT[]);
                    
                    UPDATE temp_pgtest_mock
                    SET times_called = times_called + 1
                      , called_with_arguments = array_to_json(array_append(array(SELECT * FROM json_array_elements(called_with_arguments)), s_arguments))
                    WHERE mock_id = s_mock_id;

                    %6$s %7$s.%8$s(%9$s);
                  END
                  $MOCK$ LANGUAGE plpgsql
                    SECURITY %10$s
                    SET search_path=%1$s, pg_temp;'
  , j_original_function_description->>'routine_schema'
  , j_original_function_description->>'routine_name'
  , pgtest.f_get_function_parameters(j_original_function_description)
  , j_original_function_description->>'routine_data_type'
  , s_mock_id
  , s_call_method
  , s_mock_function_schema_name
  , s_mock_function_name
  , (SELECT string_agg(t.names, ',') FROM (SELECT json_array_elements_text(j_original_function_description->'parameter_names') AS names) t)
  , j_original_function_description->>'security_type'
  );
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.run_tests(s_schema_names VARCHAR[])
  RETURNS int AS
$$
DECLARE
  s_function_name VARCHAR;
  s_schema_name VARCHAR;
  t_start_time TIMESTAMP;
  t_end_time TIMESTAMP;
  s_test_result VARCHAR;
  i_test_count INT := 0;
  i_error_count INT := 0;
BEGIN
  t_start_time := clock_timestamp();

  FOREACH s_schema_name IN ARRAY s_schema_names LOOP
    RAISE NOTICE 'Running tests in schema: %', s_schema_name;
    FOR s_function_name IN (SELECT function_name FROM pgtest.f_get_test_functions_in_schema(s_schema_name))
    LOOP
      i_test_count := i_test_count + 1;
      RAISE NOTICE 'Running test: %.%', s_schema_name, s_function_name;
      s_test_result := pgtest.f_run_test(s_schema_name, s_function_name);
      RAISE NOTICE '%', s_test_result;
      IF (s_test_result <> 'OK') THEN
        i_error_count := i_error_count + 1;
      END IF;
    END LOOP;
  END LOOP;

  t_end_time := clock_timestamp();
  RAISE NOTICE 'Executed % tests of which % failed in %', i_test_count, i_error_count, (t_end_time - t_start_time);
  RAISE 'PgTest ended.'; -- To rollback all changes that were made during tests.
EXCEPTION
  WHEN OTHERS THEN
    RETURN i_error_count;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.run_tests(s_schema_name VARCHAR)
  RETURNS int AS
$$
BEGIN
  RETURN pgtest.run_tests(ARRAY[s_schema_name]);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;

----------------
-- ASSERTIONS --
----------------

DO LANGUAGE plpgsql $BODY$
DECLARE
  s_data_type_name VARCHAR;
BEGIN
  -- Not using ANYNONARRAY, because then casting is needed.
  FOR s_data_type_name IN (
    SELECT unnest(ARRAY['BIGINT', 'BIT', 'BOOLEAN', 'CHAR', 'VARCHAR', 'DOUBLE PRECISION', 'INT', 'REAL', 'SMALLINT', 'TEXT', 'TIME', 'TIMETZ', 'TIMESTAMP', 'TIMESTAMPTZ', 'XML'])
  ) LOOP
    EXECUTE format('CREATE OR REPLACE FUNCTION pgtest.assert_equals(s_expected_value %s, s_real_value %1$s, s_message TEXT DEFAULT ''Expected: %%1$s. But was: %%2$s.'')
                      RETURNS void AS
                    $$
                    BEGIN
                      IF (NOT(s_expected_value = s_real_value)) THEN
                        RAISE EXCEPTION ''%%'', format(s_message, s_expected_value, s_real_value);
                      END IF;
                    END
                    $$ LANGUAGE plpgsql
                      SECURITY DEFINER
                      SET search_path=pgtest, pg_temp;', s_data_type_name);

    EXECUTE format('CREATE OR REPLACE FUNCTION pgtest.assert_not_equals(s_not_expected_value %s, s_real_value %1$s, s_message TEXT DEFAULT ''Not expected: %%1$s. But was: %%2$s.'')
                      RETURNS void AS
                    $$
                    BEGIN
                      IF (s_not_expected_value = s_real_value) THEN
                        RAISE EXCEPTION ''%%'', format(s_message, s_not_expected_value, s_real_value);
                      END IF;
                    END
                    $$ LANGUAGE plpgsql
                      SECURITY DEFINER
                      SET search_path=pgtest, pg_temp;', s_data_type_name);
  END LOOP;
END
$BODY$;


CREATE OR REPLACE FUNCTION pgtest.assert_equals(a_expected_array ANYARRAY, a_actual_array ANYARRAY, s_message TEXT DEFAULT 'Expected: %1$s. But was: %2$s.')
  RETURNS void AS
$$
BEGIN
  IF (NOT(a_expected_array = a_actual_array)) THEN
    RAISE EXCEPTION '%', format(s_message, a_expected_array, a_actual_array);
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.assert_not_equals(a_not_expected_array ANYARRAY, a_actual_array ANYARRAY, s_message TEXT DEFAULT 'Not expected: %1$s. But was: %2$s.')
  RETURNS void AS
$$
BEGIN
  IF (a_not_expected_array = a_actual_array) THEN
    RAISE EXCEPTION '%', format(s_message, a_not_expected_array, a_actual_array);
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.assert_true(b_value BOOLEAN, s_message TEXT DEFAULT 'Expected: TRUE. But was: FALSE.')
  RETURNS void AS
$$
BEGIN
  IF (NOT(b_value)) THEN
    RAISE EXCEPTION '%', s_message;
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.assert_false(b_value BOOLEAN, s_message TEXT DEFAULT 'Expected: FALSE. But was: TRUE.')
  RETURNS void AS
$$
BEGIN
  IF (b_value) THEN
    RAISE EXCEPTION '%', s_message;
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.assert_query_equals(s_expected_recordset TEXT[][], s_sql_query TEXT, s_message TEXT DEFAULT 'Expected: %1$s. But was: %2$s.')
  RETURNS void AS
$$
DECLARE
  s_actual_recordset TEXT[][];
BEGIN
  EXECUTE format('SELECT pgtest.array_agg_mult(ARRAY[t.values]) FROM (
                    SELECT pgtest.f_json_object_values_to_array(row_to_json(query)) AS values
                    FROM (%s) query
                  ) t;', s_sql_query) INTO s_actual_recordset;
  PERFORM pgtest.assert_equals(s_expected_recordset, s_actual_recordset, s_message);
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;

-------------
-- MOCKING --
-------------

CREATE OR REPLACE FUNCTION pgtest.simple_mock(s_original_function_schema_name VARCHAR, s_original_function_name VARCHAR, s_function_arguments VARCHAR, s_mock_function_schema_name VARCHAR, s_mock_function_name VARCHAR)
  RETURNS void AS
$$
DECLARE
  s_mock_id VARCHAR := 'pgtest_mock_' || md5(random()::text) || '_' || nextval('pgtest.unique_id');
BEGIN
  EXECUTE 'ALTER FUNCTION ' || s_original_function_schema_name || '.' || s_original_function_name || '(' || s_function_arguments || ') RENAME TO ' || s_original_function_name || '_' || s_mock_id || ';';

  EXECUTE 'ALTER FUNCTION ' || s_mock_function_schema_name || '.' || s_mock_function_name || '(' || s_function_arguments || ') RENAME TO ' || s_original_function_name ||';';

  IF (s_mock_function_schema_name <> s_original_function_schema_name) THEN
    EXECUTE 'ALTER FUNCTION ' || s_mock_function_schema_name || '.' || s_original_function_name || '(' || s_function_arguments || ') SET SCHEMA ' || s_original_function_schema_name || ';';
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.mock(s_original_function_schema_name VARCHAR, s_original_function_name VARCHAR, s_function_argument_types VARCHAR[], s_mock_function_schema_name VARCHAR, s_mock_function_name VARCHAR)
  RETURNS varchar AS
$$
DECLARE
  s_mock_id VARCHAR := 'pgtest_mock_' || md5(random()::text) || '_' || nextval('pgtest.unique_id');
  j_original_function_description JSON;
BEGIN
  j_original_function_description := pgtest.f_get_function_description(s_original_function_schema_name, s_original_function_name, s_function_argument_types);
  IF (j_original_function_description IS NULL) THEN
    RAISE EXCEPTION 'Could not find function to mock: %.%(%)', s_original_function_schema_name, s_original_function_name, array_to_string(s_function_argument_types, ',');
  END IF;

  CREATE TEMP TABLE IF NOT EXISTS temp_pgtest_mock(
    mock_id VARCHAR UNIQUE
  , times_called INT DEFAULT 0
  , called_with_arguments JSON DEFAULT '[]'::JSON
  ) ON COMMIT DROP;

  INSERT INTO temp_pgtest_mock(mock_id) VALUES (s_mock_id);

  EXECUTE 'ALTER FUNCTION ' || s_original_function_schema_name || '.' || s_original_function_name || '(' || array_to_string(s_function_argument_types, ',') || ') RENAME TO ' || s_original_function_name || '_' || s_mock_id || ';';

  PERFORM pgtest.f_create_mock_function(s_mock_id, j_original_function_description, s_mock_function_schema_name, s_mock_function_name);

  RETURN s_mock_id;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.assert_mock_called(s_mock_id VARCHAR, i_expected_times_called INT DEFAULT 1, s_message TEXT DEFAULT 'Function expected to be called %1$s time(s). But it was called %2$s time(s).')
  RETURNS void AS
$$
DECLARE
  i_actual_times_called INT;
BEGIN
  SELECT times_called
  INTO i_actual_times_called
  FROM temp_pgtest_mock
  WHERE mock_id = s_mock_id;

  IF (i_actual_times_called IS NULL) THEN
    RAISE EXCEPTION 'Mock with id "%" not found.', s_mock_id;
  ELSIF (i_expected_times_called < 0) THEN
    RAISE EXCEPTION 'Expected times called must be >= 0 not %.', i_expected_times_called;
  ELSIF (i_expected_times_called <> i_actual_times_called) THEN
    RAISE EXCEPTION '%', format(s_message, i_expected_times_called, i_actual_times_called);
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


CREATE OR REPLACE FUNCTION pgtest.assert_mock_called_with_arguments(s_mock_id VARCHAR, s_expected_arguments TEXT[], i_call_time INT, s_message TEXT DEFAULT 'Function expected to be called %1$s. time with arguments %2$s. But they were %3$s.')
  RETURNS void AS
$$
DECLARE
  i_actual_times_called INT;
  j_called_with_arguments JSON;
  s_actual_arguments TEXT[];
BEGIN
  SELECT times_called, called_with_arguments
  INTO i_actual_times_called, j_called_with_arguments
  FROM temp_pgtest_mock
  WHERE mock_id = s_mock_id;

  IF (i_call_time > i_actual_times_called) THEN
    RAISE EXCEPTION 'Checking for parameters in call number % but only % call(s) were made.', i_call_time, i_actual_times_called;
  ELSIF (i_call_time < 1) THEN
    RAISE EXCEPTION 'Call time must be >= 1 not %.', i_call_time;
  END IF;

  SELECT array(SELECT json_array_elements_text((j_called_with_arguments)->(i_call_time-1))) INTO s_actual_arguments;

  IF (NOT(array(SELECT json_array_elements_text((j_called_with_arguments)->(i_call_time-1))) = s_expected_arguments)) THEN
    RAISE EXCEPTION '%', format(s_message, i_call_time, s_expected_arguments, s_actual_arguments);
  END IF;
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest, pg_temp;


DO LANGUAGE plpgsql $$
BEGIN
  RAISE NOTICE 'PgTest installed!';
END
$$;