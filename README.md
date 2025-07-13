
## Snowflake Streamlit App: Service Account Secret Management

This infographic provides a visual guide to the Service Account Secret Management application, a Streamlit tool designed to simplify the process of updating and disabling service account secrets in Snowflake. It outlines the application's user-friendly, three-step process, from selecting an action to executing the change through a secure stored procedure.

---

### **Service Account Secret Management: A Visual Guide**

**A Streamlit Application for Secure and Simple Snowflake Service Account Updates**

---

#### **Step 1: Choose an Action**

Start by deciding the operation you want to perform on the service account. The user interface will dynamically adjust based on your selection.

* **UPDATE**: Select this to change a service account's password or RSA keypair. This choice will reveal further options for specifying the secret type.
* **DISABLE**: Choose this option to deactivate a service account. The interface will simplify, presenting only the necessary fields for this action.

---

#### **Step 2: Select the Secret Type (for Update Action)**

If you chose to "UPDATE," you will then specify the kind of secret you are changing.

* **PASSWORD**: This selection will display a field for you to enter the new password for the service account.
* **KEYPAIR**: This option is for updating the RSA public and private keys. It will present fields for the key number, the public key, and the private key.

---

#### **Step 3: Provide Details and Execute**

The final step involves inputting the specific details of the service account and the new secret, then executing the change.

1.  **Enter Service Account Information**:
    * **Service Account Name**: The name of the user account you are modifying.
    * **Service Account Owner Role**: The role that has ownership of the service account, which is typically the `ACCOUNTADMIN` role.

2.  **Input Secret Values**:
    * If you're updating a **password**, enter the new password.
    * If you're updating a **keypair**, specify the RSA key number (1 or 2) and paste the corresponding public and private keys.

3.  **Execute**:
    * Click the "Execute Change" button.
    * This action calls the `CHANGE_SERVICE_ACCOUNT_SECRET_PROC` stored procedure in Snowflake, which securely performs the requested update or disabling of the account.
    * A success or error message will be displayed, confirming the outcome of the operation.
