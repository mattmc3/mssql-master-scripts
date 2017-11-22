use master
go
if objectproperty(object_id('meta.script_object_definition'), 'IsProcedure') is null begin
    exec('create proc meta.script_object_definition as')
end
go
--------------------------------------------------------------------------------
-- Proc: script_object_definition
-- Author: mattmc3
-- Revision: 20171122.0
-- License: https://github.com/mattmc3/mssql-master-scripts/blob/master/LICENSE
-- Purpose: Generates SQL scripts for objects with SQL definitions.
--          Specifically views, sprocs, and user defined funcs.
--          Mimics SSMS scripting behavior.
-- Params: @dbname nvarchar(128): Name of the database
--         @object_type nvarchar(100): The type of script to generate:
--             - ALL (<NULL>)
--             - VIEW
--             - PROCEDURE
--             - FUNCTION
--         @create_or_alter_header nvarchar(100): The header syntax:
--             - CREATE
--             - ALTER
--             - DROP
--             - DROP AND CREATE
--             - CREATE OR ALTER
--         @format nvarchar(100): Defines the output format
--             - 'Generate Scripts': Matches "Tasks, Generate Scripts"
--             - 'SSMS Object Explorer': generates code to match SSMS
--                format
--------------------------------------------------------------------------------
alter proc meta.script_object_definition
    @dbname nvarchar(128)
    ,@object_type nvarchar(100) = null
    ,@create_or_alter_header nvarchar(100) = 'CREATE OR ALTER'
    ,@object_schema nvarchar(128) = null
    ,@object_name nvarchar(128) = null
    ,@format nvarchar(100) = null
    ,@include_header_comment bit = 1
    ,@tab_replacement varchar(10) = null
as
begin

set nocount on

-- Temporarily uncomment for inline testing
--declare @dbname nvarchar(128) = 'master'
--      , @create_or_alter_header nvarchar(100) = 'drop and create'
--      , @object_schema nvarchar(128) = null
--      , @object_name nvarchar(128) = null

declare @err nvarchar(4000)
      , @database_id int

select @database_id = database_id
from sys.databases
where name = @dbname

if @database_id is null begin
    set @err = 'The database provided does not exist: ' + isnull(@dbname, '<NULL>')
    raiserror(@err, 16, 10)
    return
end

set @create_or_alter_header = isnull(@create_or_alter_header, 'CREATE')
set @object_type = isnull(@object_type, 'ALL')

if @create_or_alter_header not in ('CREATE', 'DROP', 'DROP AND CREATE', 'CREATE OR ALTER') begin
    set @err = 'The @create_or_alter_header values supported are ''CREATE'', ''DROP'', ''DROP AND CREATE'', and ''CREATE OR ALTER'''
    raiserror(@err, 16, 10)
    return
end

set @tab_replacement = isnull(@tab_replacement, char(9))

if @format is null or @format not in ('SSMS Object Explorer', 'Generate Scripts') begin
    set @format = 'Generate Scripts'
end

declare @has_drop bit = 0
      , @has_definition bit = 1
      , @now datetime = getdate()

if @object_name is not null begin
    set @object_schema = isnull(@object_schema, 'dbo')
end

if @create_or_alter_header in ('DROP', 'DROP AND CREATE') begin
    set @has_drop = 1
end

if @create_or_alter_header in ('DROP') begin
    set @has_definition = 0  -- false
end

-- refresh ====================================================================
exec meta.refresh_metadata @dbname, 'meta.schemas,meta.objects,meta.sql_modules,meta.extended_properties'

-- get definitions ============================================================
declare @defs table (
    object_id int not null
    ,object_catalog nvarchar(128) not null
    ,object_schema nvarchar(128) not null
    ,object_name nvarchar(128) not null
    ,quoted_name nvarchar(500) not null
    ,object_definition nvarchar(max) null
    ,uses_ansi_nulls bit null
    ,uses_quoted_identifier bit null
    ,is_schema_bound bit null
    ,object_type_code char(2) null
    ,object_type varchar(10) not null
    ,object_language varchar(10) not null
)

insert into @defs
select obj.object_id as object_id
     , @dbname as object_catalog
     , sch.name as object_schema
     , obj.name as object_name
     , quotename(sch.name) + '.' + quotename(obj.name) as quoted_name
     , sm.definition as object_definition
     , sm.uses_ansi_nulls
     , sm.uses_quoted_identifier
     , sm.is_schema_bound
     , obj.type as object_type_code
     , case when obj.type in ('V') then 'VIEW'
            when obj.type in ('P', 'PC') then 'PROCEDURE'
            else 'FUNCTION'
       end as object_type
     , case when obj.type in ('V', 'P', 'FN', 'TF', 'IF') then 'SQL'
            else 'EXTERNAL'
       end as object_language
from meta.objects obj
join meta.schemas sch on obj.database_id = sch.database_id
                     and obj.schema_id = sch.schema_id
left join meta.sql_modules sm on sm.database_id = obj.database_id
                             and sm.object_id = obj.object_id
where obj.database_id = @database_id
  and obj.type in ('V', 'P', 'FN', 'TF', 'IF', 'AF', 'FT', 'IS', 'PC', 'FS')
  and obj.is_ms_shipped = 0
  and obj.object_id not in (
        select major_id
          from meta.extended_properties ep
         where ep.database_id = @database_id
           and ep.minor_id = 0
           and ep.class = 1
           and ep.name = N'microsoft_database_tools_support'
)
order by 1, 2, 3

-- whittle down
delete from @defs
where (@object_schema is not null and object_schema <> @object_schema)
or (@object_name is not null and object_name <> @object_name)

-- standardize on newlines for split
update @defs
set object_definition = replace(object_definition, char(13) + char(10), char(10))

-- standardize tabs
if @tab_replacement <> char(9) begin
    update @defs
    set object_definition = replace(object_definition, char(9), @tab_replacement)
end


-- result ======================================================================
declare @result table (
    object_catalog nvarchar(128)
    ,object_schema nvarchar(128)
    ,object_name nvarchar(128)
    ,object_type nvarchar(128)
    ,seq int
    ,ddl nvarchar(max)
)


-- header ======================================================================
if @format = 'Generate Scripts' begin
    -- just one database
    insert into @result (
        object_catalog
        ,object_schema
        ,object_name
        ,object_type
        ,seq
        ,ddl
    )
    select
        a.object_catalog
        ,'' as object_schema
        ,'' as object_name
        ,'' as object_type
        ,0
        ,case b.seq
            when 1 then 'USE ' + quotename(a.object_catalog)
            when 2 then 'GO'
        end as ddl
    from (select distinct object_catalog from @defs) a
    cross apply (select 1 as seq union
                 select 2) b
end
else begin
    insert into @result (
        object_catalog
        ,object_schema
        ,object_name
        ,object_type
        ,seq
        ,ddl
    )
    select
        a.object_catalog
        ,a.object_schema
        ,a.object_name
        ,a.object_type
        ,100000000 + b.seq
        ,case b.seq
            when 1 then 'USE ' + quotename(a.object_catalog)
            when 2 then 'GO'
            when 3 then ''
        end as ddl
    from @defs a
    cross apply (select 1 as seq union
                 select 2 union
                 select 3) b
end


-- drops =======================================================================
if @has_drop = 1 begin
    insert into @result (
        object_catalog
        ,object_schema
        ,object_name
        ,object_type
        ,seq
        ,ddl
    )
    select
        a.object_catalog
        ,a.object_schema
        ,a.object_name
        ,a.object_type
        ,200000000 + b.seq
        ,case
            when b.seq = 1 and @include_header_comment = 1 then '/****** Object:  ' +
                case a.object_type
                    when 'VIEW' then 'View'
                    when 'PROCEDURE' then 'StoredProcedure'
                    when 'FUNCTION' then 'UserDefinedFunction'
                    else ''
                end + ' ' + a.quoted_name + '    Script Date: ' + format(@now, 'M/d/yyyy h:mm:ss tt') + ' ******/'
            when b.seq = 2 then 'DROP ' + a.object_type + ' ' + a.quoted_name
            when b.seq = 3 then 'GO'
            when b.seq = 4 then ''
            else null
        end as ddl
    from @defs a
    cross apply (select 1 as seq union
                 select 2 union
                 select 3 union
                 select 4) b
end

-- Parse DDL into one record per line ==========================================
-- I could use string_split but the documentation does not specify that order is
-- preserved, and that is crucial to this parse. Also, string_split is 2016+.
if @has_definition = 1 begin
    declare @ddl_parse table (
        object_id int
        ,seq int
        ,start_idx int
        ,end_idx int
    )

    declare @rc int = -1
    declare @seq int = 1
    while @rc <> 0 begin
        insert into @ddl_parse (
            object_id
            ,seq
            ,start_idx
            ,end_idx
        )
        select
            d.object_id
            ,@seq as seq
            ,isnull(p.end_idx, 0) + 1 as start_idx
            ,isnull(nullif(charindex(char(10), d.object_definition, isnull(p.end_idx, 0) + 1), 0), len(d.object_definition) + 1) as end_idx
        from @defs d
        left join @ddl_parse p
            on d.object_id = p.object_id
            and p.seq = @seq - 1
        where @seq = 1
           or p.end_idx <= len(d.object_definition)

        set @rc = @@rowcount
        set @seq = @seq + 1
    end

    -- Add DDL lines to result =================================================
    insert into @result (
        object_catalog
        ,object_schema
        ,object_name
        ,object_type
        ,seq
        ,ddl
    )
    select d.object_catalog
         , d.object_schema
         , d.object_name
         , d.object_type
         , p.seq + 500000000  -- start with a high sequence so that we can add header/footer sql
         , substring(d.object_definition, p.start_idx, p.end_idx - p.start_idx) as ddl
    from @defs d
    join @ddl_parse p
            on d.object_id = p.object_id
    order by d.object_id, p.seq

    -- Wrap the SQL statements with boiler plate ===============================
    insert into @result (
        object_catalog
        ,object_schema
        ,object_name
        ,object_type
        ,seq
        ,ddl
    )
    select
        a.object_catalog
        ,a.object_schema
        ,a.object_name
        ,a.object_type
        ,300000000 + b.seq
        ,case
            when b.seq = 1 and @include_header_comment = 1 then '/****** Object:  ' +
                case a.object_type
                    when 'VIEW' then 'View'
                    when 'PROCEDURE' then 'StoredProcedure'
                    when 'FUNCTION' then 'UserDefinedFunction'
                    else ''
                end + ' ' + a.quoted_name + '    Script Date: ' + format(@now, 'M/d/yyyy h:mm:ss tt') + ' ******/'
            when b.seq = 2 then 'SET ANSI_NULLS ' + case when a.uses_ansi_nulls = 1 then 'ON' else 'OFF' end
            when b.seq = 3 then 'GO'
            when b.seq = 4 then ''
            when b.seq = 5 then 'SET QUOTED_IDENTIFIER ' + case when a.uses_quoted_identifier = 1 then 'ON' else 'OFF' end
            when b.seq = 6 then 'GO'
            when b.seq = 7 then ''
            else null
        end as ddl
        from @defs a
        cross apply (select 1 as seq union
                     select 2 union
                     select 3 union
                     select 4 union
                     select 5 union
                     select 6 union
                     select 7) b

        insert into @result (
            object_catalog
            ,object_schema
            ,object_name
            ,object_type
            ,seq
            ,ddl
        )
        select
            a.object_catalog
            ,a.object_schema
            ,a.object_name
            ,a.object_type
            ,800000000 + b.seq
            ,case b.seq
                when 1 then 'GO'
                when 2 then ''
            end as ddl
        from @defs a
        cross apply (select 1 as seq union
                     select 2) b
end

-- Fix the create statement ====================================================
if @create_or_alter_header in ('create', 'alter', 'create or alter') begin
    ;with cte as (
        select *
             , row_number() over (partition by object_schema, object_name
                                  order by seq) as rn
        from (
            select *
                 , patindex('%create%' +
                   case when object_type = 'PROCEDURE' then 'PROC'
                        else object_type
                   end + '%' + object_schema + '%.%' + object_name + '%', ddl) as create_idx
            from @result
        ) a
        where create_idx > 0
    )
    update cte
    set ddl = replace(case when ascii(left(ltrim(substring(ddl, create_idx + 6, 8000)), 1)) between 97 and 122
                           then lower(@create_or_alter_header)
                           else @create_or_alter_header
                      end + ' ' + ltrim(substring(ddl, create_idx + 6, 8000))
                      ,object_schema + '.' + object_name
                      ,quotename(object_schema) + '.' + quotename(object_name))
    where rn = 1
end


-- Clean up based on formatting
if @format = 'Generate Scripts' begin
    -- remove blank lines
    delete from @result
    where seq / 100000000 in (3, 8)
    and ddl = ''
end

-- Return the result data ======================================================
delete from @result
where ddl is null

select *
from @result r
where r.object_type = @object_type
or @object_type = 'ALL'
order by 4, 1, 2, 3, 5

end

go
