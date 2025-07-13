import streamlit as st
from snowflake.snowpark.context import get_active_session

# --- App Configuration ---
st.set_page_config(
    page_title="Service Account Management",
    page_icon="🔑",
    layout="centered",
)

# --- Snowpark Session ---
# Attempt to get the active Snowpark session, otherwise stop the app.
try:
    session = get_active_session()
except Exception:
    st.error("Could not get active Snowflake session. Please run this app in a Snowflake environment.")
    st.stop()

# --- Page Title and Description ---
st.title("🔑 Service Account Secret Management")
st.write(
    "This application provides a user-friendly interface to update or disable "
    "service account secrets by calling the `CHANGE_SERVICE_ACCOUNT_SECRET_PROC` stored procedure."
)

# --- Show Current User and Role ---
try:
    current_user_role_df = session.sql("SELECT CURRENT_USER(), CURRENT_ROLE()").collect()
    current_user = current_user_role_df[0][0]
    current_role = current_user_role_df[0][1]
    st.info(f"**Running as User:** `{current_user}` | **With Role:** `{current_role}`")
except Exception as e:
    st.warning(f"Could not retrieve current user and role: {e}")

# --- Main Interaction Frame ---
# A single container with a border holds all interactive steps for a unified UI.
with st.container(border=True):
    # --- Step 1: Action Selector ---
    # This is kept outside the form to allow the UI to react instantly to changes.
    st.header("Step 1: Choose an Action")
    action = st.radio(
        "Action",
        ("UPDATE", "DISABLE"),
        index=0,
        key="action_selector",
        horizontal=True,
        label_visibility="collapsed",
        help="Choose 'UPDATE' to change a secret or 'DISABLE' to deactivate the account."
    )

    # --- Initialize secret_type ---
    secret_type = None

    # --- Step 2: Secret Type Selector (Conditional) ---
    # This is also outside the form to ensure the UI updates immediately.
    # It only appears if the action is 'UPDATE'.
    if action == 'UPDATE':
        st.header("Step 2: Choose Secret Type")
        secret_type = st.radio(
            "Secret Type",
            ("PASSWORD", "KEYPAIR"),
            key="secret_type_selector",
            horizontal=True,
            label_visibility="collapsed",
            help="Select the type of secret to update."
        )

    # --- Main Form for Final Details and Execution ---
    with st.form("service_account_form"):
        st.header("Step 3: Provide Details & Execute")

        # --- Service Account Details in a two-column layout ---
        col_details_1, col_details_2 = st.columns(2)
        with col_details_1:
            service_account_name = st.text_input(
                "Service Account Name",
                placeholder="e.g., SERVICE ACCOUNT",
                help="The name of the user account to modify."
            )
        with col_details_2:
            service_account_owner = st.text_input(
                "Service Account Owner Role",
                "ACCOUNTADMIN",
                help="The role that owns the service account (typically ACCOUNTADMIN)."
            )

        # --- Initialize variables for submission ---
        secret_value_1 = 'NULL'
        secret_value_2 = 'NULL'
        rsa_key_number = '0'

        # --- Conditional input fields for the selected secret type ---
        if action == 'UPDATE':
            st.markdown("---") # Visual separator
            if secret_type == 'PASSWORD':
                secret_value_1 = st.text_input(
                    "New Password",
                    type="password",
                    key="password_input",
                    help="Enter the new password for the service account."
                )
            elif secret_type == 'KEYPAIR':
                rsa_key_number = st.selectbox(
                    "RSA Key Number",
                    ('1', '2'),
                    key="rsa_key_selector",
                    help="Specify which RSA key to update (RSA_PUBLIC_KEY or RSA_PUBLIC_KEY_2)."
                )
                secret_value_1 = st.text_area(
                    "RSA Public Key",
                    height=150,
                    key="rsa_pub_key_input",
                    help="Paste the full public key value."
                )
                secret_value_2 = st.text_area(
                    "RSA Private Key (for history record)",
                    height=150,
                    key="rsa_priv_key_input",
                    help="Paste the corresponding private key. This is stored for auditing, not used in the ALTER USER command."
                )

        # --- Form Submission ---
        st.write("---") # Visual separator
        submitted = st.form_submit_button("Execute Change")

        if submitted:
            # --- Input Validation ---
            error_found = False
            if not service_account_name:
                st.warning("Service Account Name is required.")
                error_found = True

            if action == 'UPDATE':
                if secret_type == 'PASSWORD' and not secret_value_1:
                    st.warning("New Password is required for a password update.")
                    error_found = True
                elif secret_type == 'KEYPAIR':
                    if not secret_value_1:
                        st.warning("RSA Public Key is required for a keypair update.")
                        error_found = True
                    if not secret_value_2:
                        st.warning("RSA Private Key is required for a keypair update.")
                        error_found = True
            
            # --- Stored Procedure Execution ---
            if not error_found:
                with st.spinner("Executing stored procedure..."):
                    try:                       
                        # Prepare parameters for the stored procedure call
                        proc_params = [
                            action,
                            service_account_name,
                            service_account_owner,
                            secret_type if action == 'UPDATE' else 'NULL',
                            secret_value_1,
                            secret_value_2,
                            rsa_key_number
                        ]
                        #st.info(proc_params)
                        # Call the stored procedure
                        sql_call = "CALL UTILS_DB.ACCOUNTADMIN_UTILS.CHANGE_SERVICE_ACCOUNT_SECRET_PROC(?, ?, ?, ?, ?, ?, ?)"
                        result_df = session.sql(sql_call, params=proc_params).collect()
                        result_message = result_df[0][0]

                        # Display the result
                        if "SUCCESS" in result_message:
                            st.success(f"**Result:** {result_message}")
                        else:
                            st.error(f"**Result:** {result_message}")

                    except Exception as e:
                        st.error(f"An error occurred while calling the stored procedure: {e}")

# --- Instructions Expander ---
with st.expander("How to use this app", expanded=False):
    st.markdown("""
    This application streamlines the process of managing service account secrets in Snowflake. Follow these steps:

    **Step 1: Choose an Action**
    - Select **UPDATE** to change a service account's password or keypair.
    - Select **DISABLE** to deactivate a service account. The UI will simplify, hiding irrelevant fields.

    **Step 2: Choose Secret Type (if Updating)**
    - This step appears only if you selected `UPDATE`.
    - Choose **PASSWORD** to display the password input field.
    - Choose **KEYPAIR** to display fields for the RSA key number, public key, and private key.

    **Step 3: Provide Details & Execute**
    1.  Enter the **Service Account Name** and confirm the **Owner Role**.
    2.  Fill in the required secret details that appear based on your previous selections.
    3.  Click the **Execute Change** button to run the stored procedure.
    4.  The result of the operation will be displayed on the screen.
    """)
