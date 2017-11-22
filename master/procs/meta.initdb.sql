use master
go
if not exists (select name from sys.schemas where name = N'meta') begin
    exec('create schema [meta] authorization [dbo]')
end
go
if objectproperty(object_id('meta.initdb'), 'IsProcedure') is null begin
    exec('create proc meta.initdb as')
end
go
-------------------------------------------------------------------------------
-- Proc: meta.initdb
-- Author: mattmc3
-- Revision: 20171122.0
-- License: https://github.com/mattmc3/mssql-master-scripts/blob/master/LICENSE
-- Purpose: Initializes database with meta objects to store SQL Server
--          schema information
-- Params: none
-------------------------------------------------------------------------------
alter proc meta.initdb as

if object_id('meta.schemas') is null begin
    create table meta.schemas (
         database_id int not null
        ,name sysname not null
        ,schema_id int not null
        ,principal_id int null
    )

    alter table meta.schemas add constraint pk_schemas primary key clustered (
        database_id
        ,schema_id
    )
end

if object_id('meta.objects') is null begin
    create table meta.objects (
         database_id int not null
        ,name sysname not null
        ,object_id int not null
        ,principal_id int null
        ,schema_id int not null
        ,parent_object_id int not null
        ,type char(2) null
        ,type_desc nvarchar(60) null
        ,create_date datetime not null
        ,modify_date datetime not null
        ,is_ms_shipped bit not null
        ,is_published bit not null
        ,is_schema_published bit not null
    )

    alter table meta.objects add constraint pk_objects primary key clustered (
        database_id
        ,object_id
    )
end

if object_id('meta.tables') is null begin
    create table meta.tables (
         database_id int not null
        ,name sysname not null
        ,object_id int not null
        ,principal_id int null
        ,schema_id int not null
        ,parent_object_id int not null
        ,type char(2) null
        ,type_desc nvarchar(60) null
        ,create_date datetime not null
        ,modify_date datetime not null
        ,is_ms_shipped bit not null
        ,is_published bit not null
        ,is_schema_published bit not null
        ,lob_data_space_id int not null
        ,filestream_data_space_id int null
        ,max_column_id_used int not null
        ,lock_on_bulk_load bit not null
        ,uses_ansi_nulls bit null
        ,is_replicated bit null
        ,has_replication_filter bit null
        ,is_merge_published bit null
        ,is_sync_tran_subscribed bit null
        ,has_unchecked_assembly_data bit not null
        ,text_in_row_limit int null
        ,large_value_types_out_of_row bit null
        ,is_tracked_by_cdc bit null
        ,lock_escalation tinyint null
        ,lock_escalation_desc nvarchar(60) null
        ,is_filetable bit null
        ,is_memory_optimized bit null
        ,durability tinyint null
        ,durability_desc nvarchar(60) null
        ,temporal_type tinyint null
        ,temporal_type_desc nvarchar(60) null
        ,history_table_id int null
        ,is_remote_data_archive_enabled bit null
        ,is_external bit not null
    )

    alter table meta.tables add constraint pk_tables primary key clustered (
        database_id
        ,object_id
    )
end

if object_id('meta.columns') is null begin
    create table meta.columns (
         database_id int not null
        ,object_id int not null
        ,name sysname null
        ,column_id int not null
        ,system_type_id tinyint not null
        ,user_type_id int not null
        ,max_length smallint not null
        ,precision tinyint not null
        ,scale tinyint not null
        ,collation_name sysname null
        ,is_nullable bit null
        ,is_ansi_padded bit not null
        ,is_rowguidcol bit not null
        ,is_identity bit not null
        ,is_computed bit not null
        ,is_filestream bit not null
        ,is_replicated bit null
        ,is_non_sql_subscribed bit null
        ,is_merge_published bit null
        ,is_dts_replicated bit null
        ,is_xml_document bit not null
        ,xml_collection_id int not null
        ,default_object_id int not null
        ,rule_object_id int not null
        ,is_sparse bit null
        ,is_column_set bit null
        ,generated_always_type tinyint null
        ,generated_always_type_desc nvarchar(60) null
        ,encryption_type int null
        ,encryption_type_desc nvarchar(64) null
        ,encryption_algorithm_name sysname null
        ,column_encryption_key_id int null
        ,column_encryption_key_database_name sysname null
        ,is_hidden bit null
        ,is_masked bit null
    )

    alter table meta.columns add constraint pk_columns primary key clustered (
        database_id
        ,object_id
        ,column_id
    )
end

if object_id('meta.indexes') is null begin
    create table meta.indexes (
         database_id int not null
        ,object_id int not null
        ,name sysname null
        ,index_id int not null
        ,type tinyint not null
        ,type_desc nvarchar(60) null
        ,is_unique bit null
        ,data_space_id int null
        ,ignore_dup_key bit null
        ,is_primary_key bit null
        ,is_unique_constraint bit null
        ,fill_factor tinyint null
        ,is_padded bit null
        ,is_disabled bit null
        ,is_hypothetical bit null
        ,allow_row_locks bit null
        ,allow_page_locks bit null
        ,has_filter bit null
        ,filter_definition nvarchar(max) null
        ,compression_delay int null
    )

    alter table meta.indexes add constraint pk_indexes primary key clustered (
        database_id
        ,object_id
        ,index_id
    )
end

if object_id('meta.index_columns') is null begin
    create table meta.index_columns (
         database_id int not null
        ,object_id int not null
        ,index_id int not null
        ,index_column_id int not null
        ,column_id int not null
        ,key_ordinal tinyint not null
        ,partition_ordinal tinyint not null
        ,is_descending_key bit null
        ,is_included_column bit null
    )

    alter table meta.index_columns add constraint pk_index_columns primary key clustered (
        database_id
        ,object_id
        ,index_id
        ,index_column_id
    )
end


if object_id('meta.sql_modules') is null begin
    create table meta.sql_modules (
         database_id int not null
        ,object_id int not null
        ,definition nvarchar(max) null
        ,uses_ansi_nulls bit null
        ,uses_quoted_identifier bit null
        ,is_schema_bound bit null
        ,uses_database_collation bit null
        ,is_recompiled bit null
        ,null_on_null_input bit null
        ,execute_as_principal_id int null
        ,uses_native_compilation bit null
    )

    alter table meta.sql_modules add constraint pk_sql_modules primary key clustered (
        database_id
        ,object_id
    )
end

if object_id('meta.extended_properties') is null begin
    create table meta.extended_properties (
         database_id int not null
        ,class tinyint not null
        ,class_desc nvarchar(60) null
        ,major_id int not null
        ,minor_id int not null
        ,name sysname not null
        ,value sql_variant null
    )

    alter table meta.extended_properties add constraint pk_extended_properties primary key clustered (
        database_id
        ,major_id
        ,minor_id
    )
end

go
-- exec meta.initdb
