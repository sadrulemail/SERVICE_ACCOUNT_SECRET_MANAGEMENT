
create or replace database UTILS_DB;
create or replace schema ACCOUNTADMIN_UTILS;
create or replace schema EVENTS;

CREATE EVENT TABLE event_logs;

ALTER ACCOUNT SET EVENT_TABLE = UTILS_DB.EVENTS.event_logs;

SHOW PARAMETERS LIKE 'event_table' IN ACCOUNT;

ALTER DATABASE UTILS_DB SET LOG_LEVEL = INFO;

CREATE OR REPLACE PROCEDURE UTILS_DB.EVENTS.LOG_TASKEVENT_PROC(
    "IN_PROC_NAME" VARCHAR,
    "IN_PROC_VERSION" VARCHAR DEFAULT '1.0',
    "IN_LOG_TYPE" VARCHAR DEFAULT 'LOG',
    "IN_STEP_NAME" VARCHAR DEFAULT 'UN-NAMED',
    "IN_STEP_VERSION" VARCHAR DEFAULT '1.0',
    "IN_SECURITY_PROFILE" VARCHAR DEFAULT 'OPEN',
    "IN_COMMENTS" VARCHAR DEFAULT 'not set',
    "IN_APPLICATION" VARCHAR DEFAULT '{"missing":"missing"}'
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    log_core VARIANT;
    return_value VARIANT;
BEGIN
    -- Construct core logging object with all parameters
    log_core := OBJECT_CONSTRUCT(
        ''procedure_name'', UPPER(:IN_PROC_NAME),
        ''procedure_version'', :IN_PROC_VERSION,
        ''log_type'', UPPER(:IN_LOG_TYPE),
        ''timestamp'', CURRENT_TIMESTAMP(),
        ''snowflake_account'', CURRENT_ACCOUNT(),
        ''environment'', UTILS_DB.UTILS.GET_ENV_NAME(),
        ''step_name'', UPPER(:IN_STEP_NAME),
        ''step_version'', :IN_STEP_VERSION,
        ''security_profile'', UPPER(:IN_SECURITY_PROFILE),
        ''comments'', :IN_COMMENTS,
        ''application'', PARSE_JSON(:IN_APPLICATION)
    );
    
    -- Log to Snowflake system
    SYSTEM$LOG_INFO(:log_core);
    
    -- Return the constructed log object
    return_value := :log_core;
    
    RETURN :return_value;
    
EXCEPTION
    WHEN OTHER THEN
        -- Return detailed error information
        RETURN OBJECT_CONSTRUCT(
            ''error_type'', ''LOG_TASKEVENT_PROC_ERROR'',
            ''sqlcode'', SQLCODE,
            ''sqlerrm'', SQLERRM,
            ''sqlstate'', SQLSTATE,
            ''parameters'', OBJECT_CONSTRUCT(
                ''procedure_name'', :IN_PROC_NAME,
                ''step_name'', :IN_STEP_NAME
            )
        );
END;
';
  -- Validation Procedure: VALIDATE_SERVICE_ACCOUNT_INPUT_PARAMETERS_PROC

CREATE OR REPLACE PROCEDURE UTILS_DB.ACCOUNTADMIN_UTILS.VALIDATE_SERVICE_ACCOUNT_INPUT_PARAMETERS_PROC(
    ACTION VARCHAR,
    SERVICE_ACCOUNT_NAME VARCHAR,
    SERVICE_ACCOUNT_OWNER VARCHAR,
    SECRET_TYPE VARCHAR,
    SECRET_VALUE_1 VARCHAR,
    SECRET_VALUE_2 VARCHAR
)
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    try {
        // Validate required parameters
        if (!ACTION || !SERVICE_ACCOUNT_NAME || !SERVICE_ACCOUNT_OWNER || !SECRET_TYPE) {
            throw "Missing required parameters. ACTION, SERVICE_ACCOUNT_NAME, and SERVICE_ACCOUNT_OWNER are mandatory.";
        }
        
        if (ACTION !== 'UPDATE' && ACTION !== 'DISABLE') {
            throw "Invalid ACTION - must be UPDATE or DISABLE";
        }

        // Check if service account exists
        var userCheck = snowflake.execute({
            sqlText: `SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.USERS 
                      WHERE NAME = '${SERVICE_ACCOUNT_NAME}' AND DELETED_ON IS NULL`
        });
        
        if (!userCheck.next()) {
            throw "Service account does not exist";
        }
        
        // Validate secret values based on type
        if (ACTION === 'UPDATE') {
            if (SECRET_TYPE === 'PASSWORD' && !SECRET_VALUE_1) {
                throw "Password value is required for PASSWORD type";
            }
            
            if (SECRET_TYPE === 'KEYPAIR' && (!SECRET_VALUE_1 || !SECRET_VALUE_2)) {
                throw "Both private and public key values are required for KEYPAIR type";
            }
        }
        
        return "SUCCESS: Input parameters validated";
    } catch (err) {
        return "ERROR: " + err;
    }
$$;

--Insert New Secret Procedure: INSERT_SERVICE_ACCOUNT_NEW_SECRET_HISTORY_VALUE_PROC
CREATE OR REPLACE PROCEDURE UTILS_DB.ACCOUNTADMIN_UTILS.INSERT_SERVICE_ACCOUNT_NEW_SECRET_HISTORY_VALUE_PROC(
    SECRET_ENABLED BOOLEAN,
    SECRET_VALUE_TYPE VARCHAR,
    SECRET_VALUE VARCHAR,
    CREATION_PROGRAM_NAME VARCHAR,
    REVISION_PROGRAM_NAME VARCHAR,
	SERVICE_ACCOUNT_NAME VARCHAR,
	SECRET_KEYPAIR_PUB_VALUE VARCHAR DEFAULT NULL,
    SECRET_KEYPAIR_RSA_KEY_NUM VARCHAR DEFAULT 0
)
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    try {        
		
        snowflake.execute({
            sqlText: `INSERT INTO UTILS_DB.ACCOUNTADMIN_UTILS.SECRET_HISTORY (
                SECRET_MODIFIED_TS, SECRET_ENABLED, SECRET_VALUE_TYPE, 
                SECRET_VALUE, SECRET_KEYPAIR_PUB_VALUE, SECRET_KEYPAIR_RSA_KEY_NUMBER,
                CREATION_TS, CREATION_PROGRAM_NAME, CREATION_USER_ID_CODE,
                REVISION_TS, REVISION_PROGRAM_NAME, REVISION_USER_ID_CODE,SERVICE_ACCOUNT_NAME
            ) VALUES (                
                CURRENT_TIMESTAMP(), 
                ${SECRET_ENABLED ? 'TRUE' : 'FALSE'}, 
                '${SECRET_VALUE_TYPE}', 
                '${SECRET_VALUE}', 
               ${SECRET_KEYPAIR_PUB_VALUE === null ? 'NULL' : "'" + SECRET_KEYPAIR_PUB_VALUE + "'"}, 
                ${SECRET_KEYPAIR_RSA_KEY_NUM},
                CURRENT_TIMESTAMP(), 
                '${CREATION_PROGRAM_NAME}', 
                CURRENT_USER(),
                CURRENT_TIMESTAMP(), 
                '${REVISION_PROGRAM_NAME}', 
                CURRENT_USER(),
				'${SERVICE_ACCOUNT_NAME}'
            );`
        });
        
        return "SUCCESS: New secret history record inserted";
    } catch (err) {
        return "ERROR: " + err;
    }
$$;

-- Disable Secret Procedure: DISABLE_SERVICE_ACCOUNT_SECRET_HISTORY_VALUE_PROC
CREATE OR REPLACE PROCEDURE UTILS_DB.ACCOUNTADMIN_UTILS.DISABLE_SERVICE_ACCOUNT_SECRET_HISTORY_VALUE_PROC(
    SERVICE_ACCOUNT_NAME VARCHAR
)
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$

    try {
        snowflake.execute({
            sqlText: `UPDATE UTILS_DB.ACCOUNTADMIN_UTILS.SECRET_HISTORY
                      SET SECRET_ENABLED = FALSE,
                          REVISION_TS = CURRENT_TIMESTAMP(),
                          REVISION_PROGRAM_NAME = 'DISABLE_SERVICE_ACCOUNT_SECRET_HISTORY_VALUE_PROC',
                          REVISION_USER_ID_CODE = CURRENT_USER()
                      WHERE SERVICE_ACCOUNT_NAME = '${SERVICE_ACCOUNT_NAME}' AND ID != (SELECT MAX(ID) FROM UTILS_DB.ACCOUNTADMIN_UTILS.SECRET_HISTORY where SERVICE_ACCOUNT_NAME = '${SERVICE_ACCOUNT_NAME}') AND SECRET_ENABLED = TRUE;`
        });
        
        return "SUCCESS: Previous secret records disabled";
    } catch (err) {
        return "ERROR: " + err;
    }
$$;

-- Role Validation Procedure: VALIDATE_SERVICE_ACCOUNT_CHANGE_ROLE_PROC
CREATE OR REPLACE PROCEDURE UTILS_DB.ACCOUNTADMIN_UTILS.VALIDATE_SERVICE_ACCOUNT_CHANGE_ROLE_PROC()
RETURNS STRING
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    try {
        // Check if caller is account admin
        var roleCheck = snowflake.execute({
            sqlText: `SELECT CURRENT_ROLE() AS ROLE`
        });
        roleCheck.next();
        var currentRole = roleCheck.getColumnValue(1);
        
        if (currentRole !== 'ACCOUNTADMIN') {
			throw "User does not have required privileges to modify secrets, Only ACCOUNTADMIN allowed.";
        }
        
        return "SUCCESS: Role validation passed";
    } catch (err) {
        return "ERROR: " + err;
    }
$$;
