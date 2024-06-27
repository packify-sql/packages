/*
 * 5-configure environment.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-26
 * Updated: 2024-06-26
 *
 * Configures the Packify environment and default settings
 *
 */

/* Operate against the database we created in the previous step */
USE :database_escaped;

EXECUTE AS LOGIN = 'PackifyLogin'

    /* Create a schema for repository resources */
    EXEC sp_executesql
        N'CREATE SCHEMA [Environment];';
    
    PRINT 'Created [Environment] schema';

    /* Create a table to hold config settings */
    CREATE TABLE Environment.Settings (
        [SettingID]         INT PRIMARY KEY IDENTITY(1,1),
        [SettingName]       NVARCHAR(200) NOT NULL,
        [SettingValue]      SQL_VARIANT NOT NULL,
        [CreateDateTime]    DATETIME NOT NULL DEFAULT (GETDATE()),
        [UpdateDateTime]    DATETIME NOT NULL DEFAULT (GETDATE()),

        CONSTRAINT
            AK_Environment_Settings_SettingName
        UNIQUE (
            [SettingName]
        )
    );

    /* Create a trigger to update the UpdateDateTime column */
    EXEC sp_executesql
        N'
        CREATE TRIGGER Environment.TRG_Settings_UpdateDateTime ON Environment.Settings
        AFTER UPDATE AS BEGIN
            SET NOCOUNT ON;

            UPDATE
                Environment.Settings
            SET
                UpdateDateTime = GETDATE()
            FROM
                Environment.Settings AS a
            INNER JOIN Inserted AS b ON
                a.[SettingID] = b.[SettingID];
        END
        ';
    
    /* Register a setting for the default repository */
    DECLARE @defaultRepositoryID INT = (
        SELECT TOP 1
            [RepositoryID]
        FROM
            Remote.Repositories
        ORDER BY
            [RepositoryID] DESC
    );
        
    INSERT INTO Environment.Settings (
        [SettingName],
        [SettingValue]
    )
    VALUES (
        'DefaultRepository',
        @defaultRepositoryID
    );

    /* Register settings for dialect and platform */
    INSERT INTO Environment.Settings (
        [SettingName],
        [SettingValue]
    )
    VALUES (
        'InstallDialect',
        'mssql'
    );

    INSERT INTO Environment.Settings (
        [SettingName],
        [SettingValue]
    )
    VALUES (
        'InstallPlatform',
        'windows'
    );
    
    DECLARE @settingsCount INT = (
        SELECT
            COUNT(*)
        FROM
            Environment.Settings
    );

    PRINT CONCAT(
        'Created Environment.Settings table and populated ',
        @settingsCount,
        ' setting',
        IIF(
            @settingsCount != 1,
            's',
            ''
        )
    );

REVERT
