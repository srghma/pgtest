DROP SCHEMA IF EXISTS pgtest_test CASCADE;
CREATE SCHEMA pgtest_test;

CREATE OR REPLACE FUNCTION pgtest_test.text_equals_text_ok()
  RETURNS void AS
$$
BEGIN
  PERFORM pgtest.assert_equals('some text', 'some text');
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest_test, pg_temp;


CREATE OR REPLACE FUNCTION pgtest_test.text_equals_text_fails()
  RETURNS void AS
$$
DECLARE
  b_pass BOOLEAN := FALSE;
BEGIN
  BEGIN
    PERFORM pgtest.assert_equals('some text', 'some other text');
  EXCEPTION
    WHEN OTHERS THEN b_pass := TRUE;
  END;
  PERFORM pgtest.assert_true(b_pass, 'Texts should equal but they are not.');
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest_test, pg_temp;


CREATE OR REPLACE FUNCTION pgtest_test.text_not_equals_text_ok()
  RETURNS void AS
$$
BEGIN
  PERFORM pgtest.assert_not_equals('some text', 'some other text');
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest_test, pg_temp;


CREATE OR REPLACE FUNCTION pgtest_test.text_not_equals_text_fails()
  RETURNS void AS
$$
DECLARE
  b_pass BOOLEAN := FALSE;
BEGIN
  BEGIN
    PERFORM pgtest.assert_not_equals('some text', 'some text');
  EXCEPTION
    WHEN OTHERS THEN b_pass := TRUE;
  END;
  PERFORM pgtest.assert_true(b_pass, 'Texts should not equal but they do.');
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest_test, pg_temp;


CREATE OR REPLACE FUNCTION pgtest_test.assert_query_equals_ok()
  RETURNS void AS
$$
BEGIN
  PERFORM pgtest.assert_query_equals(ARRAY[
    ARRAY['a','b'],
    ARRAY['c','d']
  ],
  'SELECT ''a'', ''b''
   UNION ALL
   SELECT ''c'', ''d''
  '
  );
END
$$ LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path=pgtest_test, pg_temp;

SELECT pgtest.run_tests('pgtest_test');