use master
go
if objectproperty(object_id('meta.standardize_index_names'), 'IsProcedure') is null begin
    exec('create proc meta.standardize_index_names as')
end
go
-------------------------------------------------------------------------------
-- Proc: meta.standardize_index_names
-- Author: mattmc3
-- Revision: 20171122.0
-- License: https://github.com/mattmc3/mssql-master-scripts/blob/master/LICENSE
-- Purpose: Analyzes indexes and generates script to rename them to a
--          standardized name.
-- Params:
-------------------------------------------------------------------------------
alter proc meta.standardize_index_names
    @dbname sysname
    ,@table_schema nvarchar(128) = null
    ,@table_name nvarchar(128) = null
    ,@index_name nvarchar(128) = null
    ,@apply_changes bit = 0
as

set nocount on

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

-- refresh ====================================================================
exec meta.refresh_metadata @dbname, 'meta.schemas,meta.tables,meta.columns,meta.extended_properties,meta.indexes,meta.index_columns'

-- POPULATE #idx FROM sys.indexes IN THE SPECIFIED DATABASE
declare @sql nvarchar(max)
      , @NL nvarchar(max) = nchar(13) + nchar(10)

drop table if exists #idx
select i.database_id
     , i.object_id
     , i.index_id
     , s.schema_id
     , s.name as table_schema
     , t.name as table_name
     , i.name as index_name
     , i.type
     , i.type_desc
     , i.is_primary_key
     , i.is_unique
     , i.is_unique_constraint
     , i.is_padded
     , i.allow_row_locks
     , i.allow_page_locks
     , t.is_ms_shipped
  into #idx
  from meta.indexes i
  join meta.tables t  on i.database_id = t.database_id
                     and i.object_id   = t.object_id
  join meta.schemas s on s.database_id = t.database_id
                     and s.schema_id   = t.schema_id
 where i.database_id = @database_id
   and i.type <> 0
   and t.is_ms_shipped = 0
   and t.name not in ('sysdiagrams')
   and s.name not in ('sys')
   and isnull(@table_schema, s.name) = s.name
   and isnull(@table_name, t.name) = t.name
   and isnull(@index_name, i.name) = i.name

-- POPULATE #idx_cols FROM sys.indexes_columns IN THE SPECIFIED DATABASE
drop table if exists #idx_cols
select i.database_id
     , i.object_id
     , i.index_id
     , ic.column_id
     , c.name as column_name
     , ic.index_column_id
     , ic.is_descending_key
     , ic.is_included_column
     , ic.key_ordinal
     , ic.partition_ordinal
  into #idx_cols
  from #idx i
  join meta.index_columns ic on ic.database_id = i.database_id
                            and ic.object_id   = i.object_id
                            and ic.index_id    = i.index_id
  join meta.columns c        on c.database_id  = ic.database_id
                            and c.object_id    = ic.object_id
                            and c.column_id    = ic.column_id

-- pivot to get the columns used in the index. MSSQL has a hard limit of 16 cols
drop table if exists #pvt_cols
select pic.object_id
     , pic.index_id
     , max([1]) as index_column01
     , max([2]) as index_column02
     , max([3]) as index_column03
     , max([4]) as index_column04
     , max([5]) as index_column05
     , max([6]) as index_column06
     , max([7]) as index_column07
     , max([8]) as index_column08
     , max([9]) as index_column09
     , max([10]) as index_column10
     , max([11]) as index_column11
     , max([12]) as index_column12
     , max([13]) as index_column13
     , max([14]) as index_column14
     , max([15]) as index_column15
     , max([16]) as index_column16
into #pvt_cols
from (
    select x.object_id
         , x.index_id
         , row_number() over (partition by x.object_id, x.index_id
                              order by x.index_column_id) as ord
         , x.column_name
    from #idx_cols as x
    where x.is_included_column = 0
) ic
pivot (max(ic.column_name) for ic.ord in (
     [1],  [2],  [3],  [4],
     [5],  [6],  [7],  [8],
     [9], [10], [11], [12],
    [13], [14], [15], [16])) as pic
group by
      pic.object_id
    , pic.index_id

-- get the included column count
drop table if exists #idx_incl
select a.object_id
     , a.index_id
     , count(*) as included_cols_count
into #idx_incl
from #idx_cols a
where a.is_included_column = 1
group by a.object_id, a.index_id

drop table if exists #new
select i.*
     , cast(
       case when i.is_primary_key = 1 then 'pk_'
            when i.is_unique_constraint = 1 then 'un_'
            when i.is_unique = 1 then 'ux_'
            when i.type = 1 then 'cx_'
            else 'ix_'
       end as nvarchar(50)) as prefix
     , case when i.is_primary_key = 1 then i.table_name + '__'
            when i.is_unique_constraint = 1 then i.table_name + '__'
            else ''
        end +
        isnull(pc.index_column01, '') +
        isnull('__' + pc.index_column02, '') +
        isnull('__' + pc.index_column03, '') +
        isnull('__' + pc.index_column04, '') +
        isnull('__' + pc.index_column05, '') +
        isnull('__' + pc.index_column06, '') +
        isnull('__' + pc.index_column07, '') +
        isnull('__' + pc.index_column08, '') +
        isnull('__' + pc.index_column09, '') +
        isnull('__' + pc.index_column10, '') +
        isnull('__' + pc.index_column11, '') +
        isnull('__' + pc.index_column12, '') +
        isnull('__' + pc.index_column13, '') +
        isnull('__' + pc.index_column14, '') +
        isnull('__' + pc.index_column15, '') +
        isnull('__' + pc.index_column16, '') as new_index_name
     , cast(
       case when inc.included_cols_count is null then ''
            else '__inc' + cast(inc.included_cols_count as varchar(5))
       end as nvarchar(50)) as suffix
     ,cast(null as sysname) as new_index_fullname
into #new
from #idx i
join #pvt_cols pc on i.object_id = pc.object_id
                 and i.index_id = pc.index_id
left join #idx_incl as inc on i.object_id = inc.object_id
                          and i.index_id = inc.index_id

update #new
set suffix = '__etc' + suffix
where len(prefix) + len(new_index_name) + len(suffix) > 128

-- fix length to fit 128 chars
update #new
set new_index_name = left(new_index_name, 128 - len(prefix) - len(suffix))

-- Handle dupes
;with cte as (
    select *
         , row_number() over (partition by table_schema, table_name, prefix, new_index_name, suffix
                              order by index_id) as rn
    from #new
)
update cte
set prefix = stuff(prefix, 3, 0, cast(rn as varchar(10)))
where rn > 1

-- fix length to fit 128 chars again
update #new
set new_index_name = left(new_index_name, 128 - len(prefix) - len(suffix))

update #new
set new_index_fullname = prefix + new_index_name + suffix

-- make table of rename instructions
drop table if exists #instructions
select
    'exec sp_rename N''' + quotename(n.table_schema) + '.' + quotename(n.table_name) + '.' + quotename(n.index_name) + ''', N''' + n.new_index_fullname + ''', N''INDEX'';' as rename_sql
    ,'exec sp_rename N''' + quotename(n.table_schema) + '.' + quotename(n.table_name) + '.' + quotename(n.new_index_fullname) + ''', N''' + n.index_name + ''', N''INDEX'';' as rename_rollback_sql
    ,case when n.index_name <> n.new_index_fullname COLLATE Latin1_General_CS_AS then 1
          else 0
     end as needs_renamed
    ,*
into #instructions
from #new n

select @dbname as database_name, *
from #instructions
order by table_schema, table_name, is_primary_key desc, type, is_unique desc, new_index_fullname

if @apply_changes <> 1 begin
    return
end

-- loop through and execute the renames
declare @c cursor
      , @msg nvarchar(4000)

set @c = cursor local fast_forward for
    select i.rename_sql
    from #instructions i
    where i.needs_renamed = 1
    order by i.table_schema, i.table_name, i.is_primary_key desc, i.type, i.is_unique desc, i.new_index_fullname

open @c
fetch next from @c into @sql
while @@fetch_status = 0 begin
    set @msg = '{{timestamp}}: running sql - {{sql}}'
    set @msg = replace(replace(@msg,
                   '{{timestamp}}', sysdatetimeoffset())
                   ,'{{sql}}', @sql)
    print @msg

    set @sql = 'use ' + @dbname + @NL + @sql
    exec sp_executesql @sql

    fetch next from @c into @sql
end

-- Clean up cursor
close @c
deallocate @c

go
