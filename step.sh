#!/bin/bash

THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${THIS_SCRIPTDIR}/_utils.sh"
source "${THIS_SCRIPTDIR}/_formatted_output.sh"

# init / cleanup the formatted output
echo "" > "${formatted_output_file_path}"

function CLEANUP_ON_ERROR_FN {
	write_section_to_formatted_output "# Error"
	echo_string_to_formatted_output "See the logs for more details"
}

CONFIG_ssh_key_file_path="$HOME/.ssh/steplib_ssh_step_id_rsa"
CONFIG_is_remove_other_identities="true"

if [ -z "${SSH_RSA_PUBLIC_KEY}" ] ; then
	write_section_to_formatted_output "# Error"
	write_section_start_to_formatted_output '* Required input `$SSH_RSA_PUBLIC_KEY` not provided!'
	exit 1
fi

if [ ! -z "${SSH_KEY_SAVE_PATH}" ] ; then
	CONFIG_ssh_key_file_path="${SSH_KEY_SAVE_PATH}"
fi

if [ ! -z "${IS_REMOVE_OTHER_IDENTITIES}" ] ; then
	if [[ "${IS_REMOVE_OTHER_IDENTITIES}" == "false" ]] ; then
		CONFIG_is_remove_other_identities="false"
	fi
fi

write_section_to_formatted_output "# Configuration"
echo_string_to_formatted_output "* Path to save the RSA SSH private key: *${CONFIG_ssh_key_file_path}*"
echo_string_to_formatted_output "* Should remove other identities from the ssh-agent? *${CONFIG_is_remove_other_identities}*"

dir_path_of_key_file=$(dirname "${CONFIG_ssh_key_file_path}")
print_and_do_command_exit_on_error mkdir -p "${dir_path_of_key_file}"
echo "${SSH_RSA_PUBLIC_KEY}" > "${CONFIG_ssh_key_file_path}"
if [ $? -ne 0 ] ; then
	write_section_to_formatted_output "# Error"
	echo_string_to_formatted_output "* Failed to write the SSH key to the provided path"
	exit 1
fi

print_and_do_command_exit_on_error chmod 0600 "${CONFIG_ssh_key_file_path}"

ssh-add -l
# as stated in the man page (https://developer.apple.com/library/mac/documentation/Darwin/Reference/ManPages/man1/ssh-add.1.html)
#  ssh-add returns the exit code 2 if it could not connect to the ssh-agent
is_should_start_new_agent=0
if [ $? -eq 2 ] ; then
	echo " (i) ssh-agent not started - starting it and exporting connection information to ~/.bashrc ..."
	is_should_start_new_agent=1
else
	# ssh-agent loaded and accessible
	if [[ "${CONFIG_is_remove_other_identities}" == "true" ]] ; then
		print_and_do_command_exit_on_error ssh-add -K
		print_and_do_command_exit_on_error ssh-agent -k
		is_should_start_new_agent=1
	fi
fi

if [ ${is_should_start_new_agent} -eq 1 ] ; then
	eval $(ssh-agent)
	if [ $? -ne 0 ] ; then
		echo "[!] Failed to load SSH agent"
		CLEANUP_ON_ERROR_FN
		exit 1
	fi
	echo >> ~/.bashrc
	echo "export SSH_AUTH_SOCK=${SSH_AUTH_SOCK}" >> ~/.bashrc
fi

# No passphrase allowed, fail if ssh-add prompts for one
#  (in case the key can't be added without a passphrase)
expect <<EOD
spawn ssh-add "${CONFIG_ssh_key_file_path}"
expect {
	"Enter passphrase for" {
		exit 1
	}
	"Identity added" {
		exit 0
	}
}
send "nopass\n"
EOD
if [ $? -ne 0 ] ; then
	write_section_to_formatted_output "# Error"
	echo_string_to_formatted_output "* Failed to add the SSH key to ssh-agent with an empty passphrase."
	exit 1
fi

write_section_to_formatted_output "# Success"
echo_string_to_formatted_output "The SSH key was saved to *${CONFIG_ssh_key_file_path}*"
echo_string_to_formatted_output "and was successfully added to ssh-agent."
