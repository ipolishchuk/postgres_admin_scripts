-- Note that pg_proc.proisagg is replaced in pg 11. The release notes say: Replace system table pg_proc's proisagg and proiswindow with prokind 
-- Params:
--  $1 -- the name of the new owner
--  $2 -- regexp for "ignore these owners"
--  $3 -- dry run ( set to 'f' to actually execute the change)
-- Example:
-- select admin_setowner('source1','skip|user|regexp','t');

CREATE OR REPLACE FUNCTION admin_setowner(varchar(50), varchar(50), boolean) RETURNS void AS
$BODY$
DECLARE
pNewOwner ALIAS FOR $1;
pIgnoreTheseOwnersRegexp ALIAS FOR $2;
pDryRun ALIAS FOR $3;
v_i integer := 0;
v_sql text;

cObjects CURSOR FOR
   select 
      0 as sort_order
     ,'SCHEMA' as object
     ,quote_ident(schema_name) as name
     ,schema_owner as current_owner
     from information_schema.schemata
    WHERE schema_name NOT LIKE 'pg_%'
      and schema_owner != pNewOwner
      and schema_owner !~ pIgnoreTheseOwnersRegexp
      and schema_name !~ 'pg_catalog|information_schema|^pg_temp_'
   UNION
   select
       case c.relkind
          when 'r' then 1 
          when 'S' then 2
          when 'v' then 3
          when 'm' then 4
          when 'c' then 5
          when 'f' then 6
       end as sort_order
      ,case c.relkind
          when 'r' then 'TABLE'
          when 'S' then 'SEQUENCE'
          when 'v' then 'VIEW'
          when 'm' then 'MATERIALIZED VIEW'
          when 'c' then 'TYPE'
          when 'f' then 'FOREIGN TABLE'
          else 'UNKNOWN RELKIN '||c.relkind
       end as object
      ,quote_ident(relnamespace::regnamespace::text) || '.' || quote_ident(c.relname) as name
      ,c.relowner::regrole::text as current_owner
    from pg_class c
   where c.relkind not in ('i','t','p')
     and relnamespace::regnamespace::text !~ 'pg_catalog|information_schema|^pg_temp_'
     and c.relowner::regrole::text != pNewOwner
     and c.relowner::regrole::text !~ pIgnoreTheseOwnersRegexp
     and not (c.relkind='f' and c.relname in ('admin_setowner'))
   UNION
   select 
        7 as sort_order,
	'SERVER'  as object,
	srvname as name,
	srvowner::regrole::text as current_owner
    from pg_foreign_server
   where srvowner::regrole::text != pNewOwner
     and srvowner::regrole::text !~ pIgnoreTheseOwnersRegexp
   UNION
   select
        8 as sort_order,
        'FUNCTION'  as object,
        pronamespace::regnamespace::text||'.'||proname as name,
        proowner::regrole::text as current_owner
    from pg_proc proc
    join pg_language l
      on l.oid=proc.prolang
   where proowner::regrole::text != pNewOwner
     and proowner::regrole::text !~ pIgnoreTheseOwnersRegexp
     and pronamespace::regnamespace::text !~ 'pg_catalog|information_schema'
     and l.lanname !~ 'c'
   order by 1,3;

BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_user WHERE usename = pNewOwner) THEN                     
        RAISE EXCEPTION 'Login role not exists --> %', pNewOwner
            USING HINT = 'Please specify correct login and try again.';
    END IF;

    v_i = 0;
    FOR obj IN cObjects LOOP
        v_sql = 'ALTER '|| obj.object ||' '|| obj.name || ' OWNER TO ' || quote_ident(pNewOwner) || ';';
        if (pDryRun) 
        THEN 
           RAISE NOTICE 'Will run: % -- Current Owner: %', v_sql,obj.current_owner; 
        ELSE EXECUTE v_sql;
        END IF;
        v_i = v_i + 1;
    END LOOP;
    RAISE NOTICE '-- Set owner % for % objects --', pNewOwner, CAST(v_i AS VARCHAR);

END;
$BODY$
  LANGUAGE 'plpgsql' VOLATILE
  COST 100;
