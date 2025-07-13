CREATE OR REPLACE TABLE UTILS_DB.ACCOUNTADMIN_UTILS.SECRET_HISTORY (
    ID NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1 COMMENT 'Unique identifier of Service Principal Secret',
    SERVICE_ACCOUNT_NAME VARCHAR NOT NULL COMMENT 'The name of the service account this secret belongs to',
    SECRET_MODIFIED_TS TIMESTAMP_LTZ(9) NOT NULL COMMENT 'Modified Timestamp',
    SECRET_ENABLED BOOLEAN NOT NULL COMMENT 'Enabled/Disabled status',
    -- Added a CHECK constraint for data integrity.
    SECRET_VALUE_TYPE VARCHAR NOT NULL COMMENT 'PASSWORD or KEYPAIR' ,
    SECRET_VALUE VARCHAR COMMENT 'Password Value (encrypted)',
    SECRET_KEYPAIR_PUB_VALUE VARCHAR COMMENT 'Keypair Public key Value',
    SECRET_KEYPAIR_RSA_KEY_NUMBER INT COMMENT 'Snowflake RSA Key Value of 1 or 2',
    -- Added DEFAULT values for audit columns to automate population on insert.
    CREATION_TS TIMESTAMP_LTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP() COMMENT 'Record creation timestamp',
    CREATION_PROGRAM_NAME VARCHAR(200) NOT NULL COMMENT 'Program that created the record',
    CREATION_USER_ID_CODE VARCHAR(200) NOT NULL DEFAULT CURRENT_USER() COMMENT 'User who created the record',
    REVISION_TS TIMESTAMP_LTZ(9) COMMENT 'Last revision timestamp',
    REVISION_PROGRAM_NAME VARCHAR(200) COMMENT 'Program that last revised the record',
    REVISION_USER_ID_CODE VARCHAR(200) COMMENT 'User who last revised the record',

    -- Primary key constraint
    CONSTRAINT PK_SECRET_HISTORY PRIMARY KEY (ID)
)
COMMENT = 'Audit trail of all service account secret changes with history tracking';


-- Main Procedure: CHANGE_SERVICE_ACCOUNT_SECRET_PROC
/*
-- Updating a password
CALL UTILS_DB.ACCOUNTADMIN_UTILS.CHANGE_SERVICE_ACCOUNT_SECRET_PROC(
    'UPDATE',                     -- ACTION (UPDATE or DISABLE)
    'MY_SERVICE_ACCOUNT',         -- SERVICE_ACCOUNT_NAME
    'ACCOUNTADMIN',              -- SERVICE_ACCOUNT_OWNER
    'PASSWORD',                   -- SECRET_TYPE (PASSWORD or KEYPAIR)
    'NewSecurePassword123!',      -- SECRET_VALUE_1 (password or public key)
    'NULL',                          -- SECRET_VALUE_2 (private key if KEYPAIR)
	'0'						   -- rsa key number, for password->0, rsa-key1->1,rsa-key2->2
);
-- Updating an RSA key pair
CALL UTILS_DB.ACCOUNTADMIN_UTILS.CHANGE_SERVICE_ACCOUNT_SECRET_PROC(
    'UPDATE',
    'API_SERVICE_ACCOUNT',
    'ACCOUNTADMIN',
    'KEYPAIR',
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...',  -- Public key
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEA...',   -- Private key
	'1'
);

--Disabling a service account
CALL UTILS_DB.ACCOUNTADMIN_UTILS.CHANGE_SERVICE_ACCOUNT_SECRET_PROC(
    'DISABLE',
    'OLD_SERVICE_ACCOUNT',
    'ACCOUNTADMIN',
    'NULL',
    'NULL',
    'NULL',
	'0'
);

*/

CREATE OR REPLACE PROCEDURE UTILS_DB.ACCOUNTADMIN_UTILS.CHANGE_SERVICE_ACCOUNT_SECRET_PROC(
    ACTION VARCHAR,
    SERVICE_ACCOUNT_NAME VARCHAR,
    SERVICE_ACCOUNT_OWNER VARCHAR,
    SECRET_TYPE VARCHAR,
    SECRET_VALUE_1 VARCHAR,
    SECRET_VALUE_2 VARCHAR,
    SECRET_KEYPAIR_RSA_KEY_NUMBER VARCHAR
)
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // Define initial logging variables
    var PROCEDURE_NAME = 'CHANGE_SERVICE_ACCOUNT_SECRET_PROC';
    var PROCEDURE_VERSION = '1.0';
    var LOG_TYPE = 'LOG';
    var STEP_NAME = 'INIT';
    var STEP_VERSION = '1.0';
    var SECURITY_PROFILE = 'admin';
    var COMMENTS = "Service Account: " + SERVICE_ACCOUNT_NAME;
    
    let application = {};
    application["SERVICE_ACCOUNT_NAME"] = SERVICE_ACCOUNT_NAME;
    application["ACTION"] = ACTION;
    application["SECRET_TYPE"] = SECRET_TYPE;
    application["SECRET_KEYPAIR_RSA_KEY_NUMBER"] = SECRET_KEYPAIR_RSA_KEY_NUMBER;

    function executeAndValidate(sql) {
        var result = snowflake.execute({sqlText: sql});
        if (!result.next()) {
            throw "Procedure call returned no results";
        }
        var msg = result.getColumnValue(1);
        if (!msg.includes("SUCCESS")) {
            throw "Sub-procedure failed: " + msg;
        }
        return msg;
    }

    function normalizeSQL(sql) {
        return sql.replace(/(\r\n|\n|\r)/gm, "").replace(/^\s+|\s+$/g, '').replace(/\s+/g, ' ');
    }

    try {
        // Log start of procedure
        application["STATUS"] = "Starting procedure execution";
        logApplicationEvent();
        
        // Validate input parameters - must return SUCCESS
        STEP_NAME = "VALIDATE_INPUT";
        application["STEP"] = STEP_NAME;
        var validateInputSQL = `CALL UTILS_DB.ACCOUNTADMIN_UTILS.VALIDATE_SERVICE_ACCOUNT_INPUT_PARAMETERS_PROC(
            '${ACTION}', '${SERVICE_ACCOUNT_NAME}', '${SERVICE_ACCOUNT_OWNER}', 
            '${SECRET_TYPE}', '${SECRET_VALUE_1}', '${SECRET_VALUE_2}'
        )`;
        
        application["SQL_CMD"] = normalizeSQL(validateInputSQL);
        logApplicationEvent();
        
        var validationResult = executeAndValidate(validateInputSQL);
        application["VALIDATION_RESULT"] = validationResult;
        logApplicationEvent();
        
        // Verify user role - must return SUCCESS
        STEP_NAME = "VALIDATE_ROLE";
        application["STEP"] = STEP_NAME;
        var validateRoleSQL = `CALL UTILS_DB.ACCOUNTADMIN_UTILS.VALIDATE_SERVICE_ACCOUNT_CHANGE_ROLE_PROC()`;
        
        application["SQL_CMD"] = normalizeSQL(validateRoleSQL);
        logApplicationEvent();
        
        var roleValidationResult = executeAndValidate(validateRoleSQL);
        application["ROLE_VALIDATION_RESULT"] = roleValidationResult;
        logApplicationEvent();
        
        // Insert new secret history record - must return SUCCESS
        STEP_NAME = "INSERT_HISTORY";
        application["STEP"] = STEP_NAME;
        var insertHistorySQL = `CALL UTILS_DB.ACCOUNTADMIN_UTILS.INSERT_SERVICE_ACCOUNT_NEW_SECRET_HISTORY_VALUE_PROC(
            TRUE,
            '${SECRET_TYPE}',
            '${SECRET_VALUE_1}',                
            'CHANGE_SERVICE_ACCOUNT_SECRET_PROC',
            'CHANGE_SERVICE_ACCOUNT_SECRET_PROC',
            '${SERVICE_ACCOUNT_NAME}',
            '${SECRET_VALUE_2}',
            ${SECRET_KEYPAIR_RSA_KEY_NUMBER}
        )`;
        
        application["SQL_CMD"] = normalizeSQL(insertHistorySQL);
        logApplicationEvent();
        
        var insertResult = executeAndValidate(insertHistorySQL);
        application["INSERT_RESULT"] = insertResult;
        logApplicationEvent();
        
        // Change secret in Snowflake
        STEP_NAME = "EXECUTE_CHANGE";
        application["STEP"] = STEP_NAME;
        var changeSQL = "";
        
        if (ACTION === 'UPDATE') {
            if (SECRET_TYPE === 'PASSWORD') {
                changeSQL = `ALTER USER "${SERVICE_ACCOUNT_NAME}" SET PASSWORD = '${SECRET_VALUE_1}' DAYS_TO_EXPIRY = 90 MUST_CHANGE_PASSWORD = FALSE DISABLED = FALSE`;
            } else if (SECRET_TYPE === 'KEYPAIR') {
                if (SECRET_KEYPAIR_RSA_KEY_NUMBER === '1') {
                    changeSQL = `ALTER USER "${SERVICE_ACCOUNT_NAME}" SET RSA_PUBLIC_KEY = '${SECRET_VALUE_1}' DISABLED = FALSE`;
                } else {
                    changeSQL = `ALTER USER "${SERVICE_ACCOUNT_NAME}" SET RSA_PUBLIC_KEY_2 = '${SECRET_VALUE_1}' DISABLED = FALSE`;
                }
            }
        } else if (ACTION === 'DISABLE') {
            changeSQL = `ALTER USER "${SERVICE_ACCOUNT_NAME}" SET DISABLED = TRUE`;
        }
        
        application["SQL_CMD"] = normalizeSQL(changeSQL);
        logApplicationEvent();
        
        snowflake.execute({sqlText: changeSQL});
        application["EXECUTION_RESULT"] = "Change executed successfully";
        logApplicationEvent();
        
        // Disable previous history rows - must return SUCCESS
        STEP_NAME = "DISABLE_HISTORY";
        application["STEP"] = STEP_NAME;
        var disableHistorySQL = `CALL UTILS_DB.ACCOUNTADMIN_UTILS.DISABLE_SERVICE_ACCOUNT_SECRET_HISTORY_VALUE_PROC(
            '${SERVICE_ACCOUNT_NAME}'
        )`;
        
        application["SQL_CMD"] = normalizeSQL(disableHistorySQL);
        logApplicationEvent();
        
        var disableResult = executeAndValidate(disableHistorySQL);
        application["DISABLE_RESULT"] = disableResult;
        logApplicationEvent();
        
        // Final success message
        application["STATUS"] = "SUCCESS: Secret updated successfully";
        logApplicationEvent();
        
        return "SUCCESS: Secret updated successfully";
    } catch (err) {
        application["STATUS"] = "ERROR: " + err;
        application["ERROR_DETAILS"] = err.stack;
        logApplicationEvent();
        return "ERROR: " + err;
    }
    
    // Helper function to log application events
    function logApplicationEvent() {
        try {
            var str_application = JSON.stringify(application);
            // Normalize the application JSON string before logging
            str_application = normalizeSQL(str_application);
            var logSQL = `call UTILS_DB.EVENTS.LOG_TASKEVENT_PROC(
                '${PROCEDURE_NAME}', 
                '${PROCEDURE_VERSION}', 
                '${LOG_TYPE}',
                '${STEP_NAME}', 
                '${STEP_VERSION}', 
                '${SECURITY_PROFILE}', 
                '${COMMENTS}', 
                '${str_application}'
            )`;
            snowflake.execute({sqlText: logSQL});
        } catch (logErr) {
            // If logging fails, we don't want to interrupt the main procedure
            // Just continue with the main execution
        }
    }
$$;