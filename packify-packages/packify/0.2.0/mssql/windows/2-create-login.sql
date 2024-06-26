/*
 * 2-create-login.sql
 *
 * Authors: Will Hinson
 * Created: 2024-06-26
 * Updated: 2024-06-26
 *
 * Creates the PackifyLogin that will own all Packify resources
 *
 */

----------------------------------------------------------------------------------------------------
DECLARE
    @ValidPasswordChars     NVARCHAR(200) = 'abcdefghijklmnopqrstuvwxyz;./,"[]{}!@#$%^&*()-_+=~',
    @PasswordLength         INT           = 128;

SET @ValidPasswordChars += UPPER(@ValidPasswordChars);
----------------------------------------------------------------------------------------------------

/* Generate a random password for the login */
DECLARE @NewPassword NVARCHAR(200) = '';
WHILE LEN(@NewPassword) != @PasswordLength BEGIN
    SET @NewPassword += SUBSTRING(
        @ValidPasswordChars,
        CAST(RAND() * LEN(@ValidPasswordChars) AS INT) + 1,
        1
    );
END

/* Generate and execute the dynamic SQL to generate the login */
DECLARE @query NVARCHAR(MAX) = CONCAT(
    '
    CREATE LOGIN
        [PackifyLogin]
    WITH
        PASSWORD = ''', @NewPassword, ''',
        DEFAULT_DATABASE = [master],
        CHECK_POLICY = ON,
        CHECK_EXPIRATION = OFF;
    '
);
EXEC sp_executesql
    @query;

PRINT CONCAT(
    'Created login PackifyLogin with password ', @NewPassword
);
PRINT 'NOTE: This password will not be displayed again';

/* Create a user on the master database for our new login */
USE [master];

CREATE USER
    [PackifyUser]
FOR LOGIN
    [PackifyLogin];

PRINT 'Created user PackifyUser in [master] for PackifyLogin';

/* Grant create database to the new user */
GRANT
    CREATE ANY DATABASE
TO
    [PackifyLogin];

PRINT 'Granted CREATE ANY DATABASE to PackifyUser';

