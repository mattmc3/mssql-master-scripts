use master
go
if objectproperty(object_id('meta.refresh_metadata'), 'IsProcedure') is null begin
    exec('create proc meta.refresh_metadata as')
end
go
-------------------------------------------------------------------------------
-- Proc: meta.refresh_metadata
-- Author: mattmc3
-- Revision: 20171122.0
-- License: https://github.com/mattmc3/mssql-master-scripts/blob/master/LICENSE
-- Purpose: Refreshes metadata tables for the specified db
-- Params:
--      @dbname: The name of the database from which to populate metadata.
--      @table_list: A comma seperated list of the tables to populate. If
--                   NULL, then all tables are populated from the target db.
-------------------------------------------------------------------------------
alter proc meta.refresh_metadata
    @dbname sysname
    ,@table_list nvarchar(4000) = null
as

set nocount on

declare @err nvarchar(4000)
      , @database_id int
      , @NL nvarchar(5) = nchar(13) + nchar(10)

select @database_id = database_id
from sys.databases
where name = @dbname

if @database_id is null begin
    set @err = 'The database provided does not exist: ' + isnull(@dbname, '<NULL>')
    raiserror(@err, 16, 10)
    return
end

declare @pop_all bit = case when @table_list is null then 1 else 0 end

-- split in SQL Server version agnostic way
-- mssql 2016+ supports string_split
declare @refresh_tables table (
    table_name nvarchar(128)
    ,object_id int
)
insert into @refresh_tables
select split.csv.value('.', 'nvarchar(128)') as value
     , object_id(split.csv.value('.', 'nvarchar(128)')) as object_id
from (
     select cast('<x>' + replace(@table_list, ',', '</x><x>') + '</x>' as xml) as data
) as csv
cross apply data.nodes('/x') as split(csv)

-- add all possible tables to refresh here
declare @alltables table (
    dest_table_name nvarchar(128)
    ,source_table_name nvarchar(128)
    ,object_id int
)
insert into @alltables (dest_table_name, source_table_name, object_id)
values ('meta.schemas', 'sys.schemas', object_id('meta.schemas'))
     , ('meta.objects', 'sys.objects', object_id('meta.objects'))
     , ('meta.tables', 'sys.tables', object_id('meta.tables'))
     , ('meta.columns', 'sys.columns', object_id('meta.columns'))
     , ('meta.indexes', 'sys.indexes', object_id('meta.indexes'))
     , ('meta.index_columns', 'sys.index_columns', object_id('meta.index_columns'))
     , ('meta.sql_modules', 'sys.sql_modules', object_id('meta.sql_modules'))
     , ('meta.extended_properties', 'sys.extended_properties', object_id('meta.extended_properties'))

if @pop_all <> 1 begin
    delete from @alltables
    where object_id not in (
        select x.object_id
        from @refresh_tables x
    )
end

-- loop through each possible refresh table
declare @c cursor
      , @object_id int
      , @dest_table_name nvarchar(128)
      , @source_table_name nvarchar(128)
      , @col_list nvarchar(max)
      , @sql nvarchar(max)

set @c = cursor local fast_forward for
    select object_id, dest_table_name, source_table_name
    from @alltables
    order by dest_table_name

open @c
fetch next from @c into @object_id, @dest_table_name, @source_table_name
while @@fetch_status = 0 begin
    -- get the list of columns for the table
    select @col_list = (
        select quotename(sc.name) + ','
        from sys.all_columns sc
        where sc.object_id = object_id(@source_table_name)
        order by sc.column_id
        for xml path('')
    )
    -- strip final comma
    select @col_list = left(@col_list, len(@col_list) - 1)

    set @sql = 'begin transaction' + @NL +
               'delete from ' + @dest_table_name + ' where database_id = ' + cast(@database_id as varchar(10)) + @NL +
               'insert into ' + @dest_table_name + '(database_id,' + @col_list + ')' + @NL +
               'select ' + cast(@database_id as varchar(10)) + ',' + @col_list + ' from ' + quotename(@dbname) + '.' + @source_table_name + @NL +
               'commit'

    --print @sql
    exec sp_executesql @sql

    -- next!
    fetch next from @c into @object_id, @dest_table_name, @source_table_name
end

-- clean up
close @c
deallocate @c

go
