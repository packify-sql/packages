/*
 * 1-check-environment.sql
 *
 * Checks that the environment allows for Packify to be installed
 * as configured. For example, the target database should not already
 * exist and we should be able to create a login for Packify
 */

DECLARE
    @errorNumber        INT,
    @errorMessage       NVARCHAR(200);

PRINT 'Check environment for installation';

/* Check that the target database doesn't exist */
IF EXISTS (
    SELECT
        *
    FROM
        sys.databases
    WHERE
        [name] = ':database_unescaped'
) BEGIN
    SET @errorNumber = 98000;
    SET @errorMessage = 'Target database :database_escaped already exists';

    GOTO Error;
END

PRINT 'PASS: Target database :database_escaped does not exist';

/* Check that the PackifyLogin doesn't already exist */
IF EXISTS (
    SELECT
        *
    FROM
        sys.syslogins
    WHERE
        [name] = 'PackifyLogin'
) BEGIN
    SET @errorNumber = 98010;
    SET @errorMessage = 'Target login PackifyLogin already exists';

    GOTO Error;
END

PRINT 'PASS: Target login PackifyLogin does not exist';

RETURN;

Error:
    THROW
        @errorNumber,
        @errorMessage,
        1;
