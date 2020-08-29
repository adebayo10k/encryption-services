#!/bin/bash
#: Title		:key-generator-and-manager.sh
#: Date			:2019-11-15
#: Author		:adebayo10k
#: Version		:1.0
#: Description	:script provides gpg encryption services to the command-line user 
#: Description	: 
#: Description	:to generate new encryption keys and revocation certs, then automatically
#: Description	:to backup configurations, revocation certs and keys in appropriate ways
#: Description	:integrate with existing system of backup, synchronisation and encryption 
#: Description	:ssh into remotes to backup their keys too
#: Options		:
##

function main
{	
	###############################################################################################
	# GLOBAL VARIABLE DECLARATIONS:
	###############################################################################################
	
	## EXIT CODES:
	E_UNEXPECTED_BRANCH_ENTERED=10
	E_OUT_OF_BOUNDS_BRANCH_ENTERED=11
	E_INCORRECT_NUMBER_OF_ARGS=12
	E_UNEXPECTED_ARG_VALUE=13
	E_REQUIRED_FILE_NOT_FOUND=20
	E_REQUIRED_PROGRAM_NOT_FOUND=21
	E_UNKNOWN_RUN_MODE=30
	E_UNKNOWN_EXECUTION_MODE=31

	export E_UNEXPECTED_BRANCH_ENTERED
	export E_OUT_OF_BOUNDS_BRANCH_ENTERED
	export E_INCORRECT_NUMBER_OF_ARGS
	export E_UNEXPECTED_ARG_VALUE
	export E_REQUIRED_FILE_NOT_FOUND
	export E_REQUIRED_PROGRAM_NOT_FOUND
	export E_UNKNOWN_RUN_MODE
	export E_UNKNOWN_EXECUTION_MODE

	###############################################################################################

	expected_no_of_program_parameters=0
	actual_no_of_program_parameters=$#

	config_file_fullpath="/etc/key_generator_and_manager.config" # a full path to a file
	line_type="" # global...
	test_line="" # global...

	declare -a file_fullpaths_to_encrypt=()

	################################################

	armor_option='--armor'

	################################################

	gpg_command='gpg'
	output_option='--output'
	file_path_placeholder='<filepath_placeholder>'

    abs_filepath_regex='^(/{1}[A-Za-z0-9\.\ _-~]+)+$' # absolute file path, ASSUMING NOT HIDDEN FILE, ...
	all_filepath_regex='^(/?[A-Za-z0-9\._-~]+)+$' # both relative and absolute file path
	email_regex='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,6}$'
	# ^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,4}$
	# ^[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:].]{2,4}$ ]]

	synchronised_location_holding_dir_fullpath= # OR synchronised_location_parent_directory
	public_keyring_default_directory_fullpath=
	revocation_certificate_default_directory_fullpath=

	this_host=$(hostname) #
	synchronised_dir_fullpath= # directory within synchronised_location_holding_dir_fullpath (only written to by this_host)
	declare -a synchronised_subdirs=() # set of directories within synchronised_dir_fullpath

	new_keygen_OK=
	new_key_rev_cert_OK=
	rev_cert_encrypt_OK=
	rev_certs_moved_OK=
	public_key_export_OK=

	##################################################

	# SET THE 'SCRIPT ROOT' DIRECTORY IN WHICH THIS SCRIPT CURRENTLY FINDS ITSELF
	echo "The absolute path to this script is: $0"
	script_root_dir="${0%'/'*}" 
	echo "Script root directory set to: $script_root_dir"
	export script_root_dir
	
	###############################################################################################

	verify_program_args
	display_program_header
	get_user_permission_to_proceed
	display_current_config_file
	get_user_config_edit_decision

	# IMPORT CONFIGURATION INTO PROGRAM VARIABLES
	import_encryption_services_configuration

	create_all_synchronised_dirs

	# CHECK THE STATE OF THE ENCRYPTION ENVIRONMENT ON WHICH THIS PROGRAM DEPENDS:
	check_encryption_platform

	# issue gpg commands to list keys for now... just to see what's there
	bash -c "gpg --list-key"
	bash -c "gpg --list-secret-keys"

	generate_and_manage_keys

	# ON RETURN OF CONTROL, CHECK FOR DESIRED POSTCONDITIONS
	echo "key_generator_and_manager exit code: $?" 

} ## end main function









###############################################################################################
#### vvvvv FUNCTION DECLARATIONS  vvvvv
###############################################################################################
# 





###############################################################################################
function verify_program_args(){

	echo "USAGE: $(basename $0)"

	# TEST COMMAND LINE ARGS
	if [ $actual_no_of_program_parameters -ne $expected_no_of_program_parameters ]
	then
		echo "Incorrect number of command line args. Exiting now..."
		echo "Usage: $(basename $0)"
		exit $E_INCORRECT_NUMBER_OF_ARGS
	fi

	echo "OUR CURRENT SHELL LEVEL IS: $SHLVL"

}

###############################################################################################
function display_program_header(){

	# Display a program header and give user option to leave if here in error:
	echo
	echo -e "		\033[33m===================================================================\033[0m";
	echo -e "		\033[33m||        Welcome to KEY GENERATION AND MANAGEMENT UTILITY        ||  author: adebayo10k\033[0m";  
	echo -e "		\033[33m===================================================================\033[0m";
	echo
		
}

###############################################################################################
function get_user_permission_to_proceed(){

	echo " Type q to quit program NOW, or press ENTER to continue."
	echo && sleep 1

	# TODO: if the shell level is -ge 2, called from another script so bypass this exit option
	read last_chance
	case $last_chance in 
	[qQ])	echo
			echo "Goodbye!" && sleep 1
			exit 0
				;;
	*) 		echo "You're IN..." && echo && sleep 1
				;;
	esac 

}

###############################################################################################
function display_current_config_file(){
	
	echo && echo CURRENT CONFIGURATION FILE...
	echo && sleep 1

	cat "$config_file_fullpath"
}

###############################################################################################
function get_user_config_edit_decision(){

	echo " Edit configuration file? [Y/N]"
	echo && sleep 1

	read edit_config
	case $edit_config in 
	[yY])	echo && echo "Opening an editor now..." && echo && sleep 2
    		sudo nano "$config_file_fullpath" # /etc exists, so no need to test access etc.
    		# also, no need to validate config file path here, since we've just edited the config file!
				;;
	[nN])	echo
			echo " Ok, using the  current configuration" && sleep 1
				;;			
	*) 		echo " Give me a Y or N..." && echo && sleep 1
			get_user_config_edit_decision
				;;
	esac 
	
}

###############################################################################################
function create_all_synchronised_dirs()
{

	# 3. WE MUST NOW ESTABLISH THAT ALL THE DIRECTORIES NEEDED FOR OUR SYSTEM OF BACKUP AND SYNCHRONISATION \
	#    +ALREADY EXIST, AND IF NOT, CREATE THEM:
	# TODO:  # mkdir -p // no error if exists (idempotent), make parents structure /a/b/c as needed MAY BE MORE EFFICIENT

	synchronised_dir_fullpath="${synchronised_location_holding_dir_fullpath}/${this_host}_gpg"
	echo && echo "synchronised_dir_fullpath variable now set to: $synchronised_dir_fullpath"

	# temporary rmdir during development, just until all directory creations confirmed working
	#rm -R "$synchronised_dir_fullpath"

	test_dir_path_access "$synchronised_dir_fullpath"
	return_code=$?
	if [ $return_code -eq 0 ]
	then
		echo "synchronised_dir_fullpath ALREADY EXISTS AND CAN BE ENTERED OK"
	else
		echo && echo "synchronised_dir_fullpath DID NOT ALREADY EXIST, SO WILL NOW BE CREATED..."
		# create it..
		mkdir "$synchronised_dir_fullpath"
		return_code=$?
		if [ $return_code -eq 0 ]
		then
			echo "synchronised_dir_fullpath CREATION WAS SUCCESSFUL"
		else
			echo "The mkdir of synchronised_dir_fullpath FAILED and returned: $return_code"
			echo "Nothing to do now, but to exit..." && echo
			exit $E_UNEXPECTED_BRANCH_ENTERED
		fi	
	fi

	synchronised_subdirs=\
(\
"${synchronised_dir_fullpath}/${this_host}_public_keys_incoming" \
"${synchronised_dir_fullpath}/${this_host}_public_keys_outgoing" \
"${synchronised_dir_fullpath}/${this_host}_revocation_certificates" \
"${synchronised_dir_fullpath}/${this_host}_public_keyring_archive" \
)

	for subdir in ${synchronised_subdirs[@]}
	do
		test_dir_path_access "$subdir"
		if [ $? -eq 0 ]
		then
			echo "subdir ALREADY EXISTS AND CAN BE ENTERED OK"
		else
			echo && echo "subdir DID NOT ALREADY EXIST, SO WILL NOW BE CREATED..."
			# create it..
			mkdir "$subdir"
			if [ $? -eq 0 ]
			then
				echo "subdir CREATION WAS SUCCESSFUL"
			else
				echo "The mkdir of subdir FAILED and returned: $?"
				echo "Nothing to do now, but to exit..." && echo
				exit $E_UNEXPECTED_BRANCH_ENTERED
			fi	
		fi
	done

}
####################################################################################################
#
function import_encryption_services_configuration()
{

echo
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo "STARTING THE 'IMPORT CONFIGURATION INTO VARIABLES' PHASE in script $(basename $0)"
echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
echo

read

get_config_values_for_all_dirs
# for these dirs:
# synchronised_location_holding_dir_fullpath
# public_keyring_default_directory_fullpath
# revocation_certificate_default_directory

# NOW DO ALL THE DIRECTORY ACCESS TESTS FOR IMPORTED PATH VALUES HERE.
# REMEMBER THAT ORDER IMPORTANT, AS RELATIVE PATHS DEPEND ON ABSOLUTE.

for dir in "$synchronised_location_holding_dir_fullpath" "$public_keyring_default_directory_fullpath"\
	"$revocation_certificate_default_directory_fullpath"
do
	# this valid form test works for sanitised directory paths too
	test_file_path_valid_form "$dir"
	return_code=$?
	if [ $return_code -eq 0 ]
	then
		echo "DIRECTORY PATH IS OF VALID FORM"
	else
		echo "The valid form test FAILED and returned: $return_code"
		echo "Nothing to do now, but to exit..." && echo
		exit $E_UNEXPECTED_ARG_VALUE
	fi	

	# if the above test returns ok, ...
	test_dir_path_access "$dir"
	return_code=$?
	if [ $return_code -eq 0 ]
	then
		echo "The full path to the DIRECTORY is: $dir"
	else
		echo "The DIRECTORY path access test FAILED and returned: $return_code"
		echo "Nothing to do now, but to exit..." && echo
		exit $E_REQUIRED_FILE_NOT_FOUND
	fi
done

}


##########################################################################################################
# test whether the configuration files' format is valid,
# and that each line contains something we're expecting
function check_config_file_content()
{
	while read lineIn
	do
		# any content problems handled in the test_and_set_line_type function:
        test_and_set_line_type "$lineIn"
        return_code="$?"
        echo "return code for tests on that line was: $return_code"
        if [ $return_code -eq 0 ]
        then
            # if tested line contained expected content
            # :
            echo "That line was expected!" && echo
        else
            echo "That line was NOT expected!"
            echo "Exiting from function \"${FUNCNAME[0]}\" in script \"$(basename $0)\""
            exit 0
        fi

	done < "$config_file_fullpath" 

}
###########################################################################################################
# returns 
function export_public_keys
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	public_key_export_OK=false
	
	echo "public_key_export_OK is set to: $public_key_export_OK"

	# ascii armour export the new public key from its' keyring to the sync'd location
	gpg --armor --output "${synchronised_dir_fullpath}/${this_host}_public_keys_outgoing/pub_key_${this_host}_$(date +'%F@%T').asc" \
	--export "$user_id"
	test_result=$?

	if [ $test_result -eq 0 ]
	then
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE EXPORT OF PUBLIC KEYS WAS SUCCESSFUL"
		public_key_export_OK=true
	else
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE EXPORT OF PUBLIC KEYS FAILED"
		public_key_export_OK=false
	fi

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	echo "public_key_export_OK was set to: $public_key_export_OK"
}
##########################################################################################################
# returns 
function rename_and_move_revocation_certificates
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	rev_certs_moved_OK=false
	
	echo "rev_certs_moved_OK is set to: $rev_certs_moved_OK"

	# rename all encrypted revocation certificates to the sync'd location
	mv "$revocation_certificate_default_directory_fullpath"/* "${synchronised_dir_fullpath}/${this_host}_revocation_certificates"
	test_result=$?

	if [ $test_result -eq 0 ]
	then
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE ENCRYPTED REVOCATION CERTS. RENAME AND MOVE WAS SUCCESSFUL"
		rev_certs_moved_OK=true
	else
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE ENCRYPTED REVOCATION CERTS. RENAME AND MOVE FAILED"
		rev_certs_moved_OK=false
	fi

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	echo "rev_certs_moved_OK was set to: $rev_certs_moved_OK"
}
##########################################################################################################
# WE KNOW THAT REVOCATION CERTS AND PRIVATE KEYS SHOULD NEVER EXIST ON THE SAME HOST, BUT WHILE REV CERTS DO \
# + EXIST ON OUR SYSTEM, WE'LL USE ENCRYPTION AND SHREDDING TO ACHEIVE CONFIDENTIALITY AND INTEGRITY
# gpg encrypt both user-generated and pre-generated revocation certs in the GnuPG default location	
function encrypt_revocation_certificates
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	rev_cert_encrypt_OK=false	
	echo "rev_cert_encrypt_OK is set to: $rev_cert_encrypt_OK"

	touch "${synchronised_dir_fullpath}/${this_host}_revocation_certificates/keypair_fingerprint_list"
	
	# we first just need to populate file_fullpaths_to_encrypt array
	# we'll also append a list of fingerprints in a synchornised location file
	# we'll use file_fullpaths_to_encrypt to create a string and pass it into file-encrypter.sh
	for file in "${revocation_certificate_default_directory_fullpath}"/*
	do
		#incoming_array+=( "${file}" )
		file_fullpaths_to_encrypt+=( "${file}" )
		if [[ $file =~ .rev$ ]]
		then
			fingerprint="${file%.rev}"; fingerprint="${fingerprint##*'/'}"
			#echo "$fingerprint"
			echo "$fingerprint" >> "${synchronised_dir_fullpath}/${this_host}_revocation_certificates/keypair_fingerprint_list"
		fi
	done

	echo && echo "file_fullpaths_to_encrypt ARRAY HAS NOW BEEN POPULATED WITH REVOCATION CERTS"

	# BASH ARRAYS ARE NOT 'FIRST CLASS VALUES' SO CAN'T BE PASSED AROUND LIKE ONE THING\
	# - so since we're only intending to make a single call\
	# to file-encrypter.sh, we need to make an IFS separated string argument
	for filename in "${file_fullpaths_to_encrypt[@]}"
	do
		#echo "888888888888888888888888888888888888888888888888888888888888888888"
		string_to_send+="${filename} " # with a trailing space character after each
	done

	# now to trim that last trailing space character:
	string_to_send=${string_to_send%[[:blank:]]}

	echo "${string_to_send}"

	# encrypt whatever we put in that file_fullpaths_to_encrypt (should normally be just 2 files\
	# - the pre and user-generated rev certs)
	
	# we want to replace EACH revocation certificate to be replaced by an encrypted version...
	# our encryption script takes care of shredding everything it encrypts!
	# TODO: THINK... WE COULD ENCRYPT WITH A DIFFERENT KEY - A KEY FOR THIS PURPOSE ONLY?
	
	echo && echo "JUST ABOUT TO CALL file-encrypter.sh ..."

	# ... so, we call file-encrypter.sh script to handle the file encryption job
	# the command argument is deliberately unquoted, so the default space character IFS DOES separate\
	# the string into arguments
	# we can use ANY available private key for this, not just the newly generated one! tell the user!
	file-encrypter.sh $string_to_send

	encrypt_result=$?
	if [ $encrypt_result -eq 0 ]
	then
		echo && echo "RETURNED VALUE \"$encrypt_result\" THEREFORE REVOCATION CERTIFICATE ENCRYPTION WAS SUCCESSFUL"
		rev_cert_encrypt_OK=true
	else
		echo && echo "RETURNED VALUE \"$encrypt_result\" THEREFORE REVOCATION CERTIFICATE ENCRYPTION FAILED"
		rev_cert_encrypt_OK=false
	fi

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	echo "rev_cert_encrypt_OK was set to: $rev_cert_encrypt_OK"
}
##########################################################################################################
# returns 
function generate_revocation_certificate
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	new_key_rev_cert_OK=false
	
	echo "new_key_rev_cert_OK is set to: $new_key_rev_cert_OK"

	# generate a revocation certificate (user-generated) for the new key-pair
	# for now we'll just hard code for an ascii (the default) format certificate

	gpg --output "${revocation_certificate_default_directory_fullpath}/revoke_cert_${this_host}_$(date +'%F@%T').asc" \
	--gen-revoke "$user_id"
	test_result=$?

	if [ $test_result -eq 0 ]
	then
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE USER-GENERATED REVOCATION CERTIFICATE WAS SUCCESSFUL"
		new_key_rev_cert_OK=true
	else
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE USER-GENERATED REVOCATION CERTIFICATE FAILED"
		new_key_rev_cert_OK=false
	fi

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	echo "new_key_rev_cert_OK was set to: $new_key_rev_cert_OK"
}
##########################################################################################################
# nothing returned, as no other function depends on the outcome of this task. just print messages.
function backup_public_keyrings
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# public keyring backup:
	for pubkeyring in {"pubring.gpg","pubring.kbx"}
	do

		# copy old public keyring (each format) from synchronised location to archive location
		test_file_path_access "${synchronised_dir_fullpath}/${pubkeyring}"
		if [ $? -eq 0 ]
		then
			echo && echo "AN EXISTING \"${pubkeyring}\" PUBLIC KEYRING WAS FOUND IN THE SYNC'D LOCATION"
			# rename and archive this existing public keyring
			mv "${synchronised_dir_fullpath}/${pubkeyring}" \
			"${synchronised_dir_fullpath}/${this_host}_public_keyring_archive/${pubkeyring}_before.$(date +'%F@%T')"
			echo && echo "THE EXISTING \"${pubkeyring}\" PUBLIC KEYRING WAS RENAMED AND ARCHIVED"
		else
			echo && echo "COULDN'T FIND AN EXISTING \"${pubkeyring}\" PUBLIC KEYRING IN THE SYNC'D LOCATION"		
		fi

		# copy new public keyring (each format) from default location to synchronised location
		test_file_path_access "$public_keyring_default_directory_fullpath/${pubkeyring}"
		if [ $? -eq 0 ]
		then
			echo && echo "A NEW \"${pubkeyring}\" PUBLIC KEYRING WAS FOUND IN THE GnuPG DEFAULT LOCATION"
			# copy the new version to the sync'd location
			cp "$public_keyring_default_directory_fullpath/${pubkeyring}" \
			"${synchronised_dir_fullpath}"
			echo && echo "THE LATEST \"${pubkeyring}\" PUBLIC KEYRING HAS NOW BEEN COPIED TO THE SYNC'D LOCATION"
		else
			echo && echo "COULDN'T FIND A NEW \"${pubkeyring}\" PUBLIC KEYRING IN THE GnuPG DEFAULT LOCATION"		
		fi

	done

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

}
##########################################################################################################
# set the value of the new_keygen_OK global
function generate_public_keypair
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	#test_uid=$1

	#new_keypair_user_id=
	new_keygen_OK=false 

	#echo "new_keypair_user_id is set to: $new_keypair_user_id"
	echo "new_keygen_OK is set to: $new_keygen_OK"


	gpg --full-gen-key	
	test_result=$?
	
	if [ $test_result -eq 0 ]
	then
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE ENCRYPTION WAS SUCCESSFUL"
		new_keygen_OK=true
	else
		echo && echo "RETURNED VALUE \"$test_result\" THEREFORE ENCRYPTION FAILED"
		new_keygen_OK=false
	fi


	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	echo "new_keygen_OK was set to: $new_keygen_OK"

}
##########################################################################################################
# returns zero if user-id (or substring of it) already used in public keyring
function test_uid_in_pub_keyring
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_uid=$1
	
	echo "test_uid is set to: $test_uid"

	gpg --list-key | grep "$test_uid" &>/dev/null
	test_result=$?

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}
##########################################################################################################
# returns zero if 
function test_email_valid_form
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_email=$1
	
	echo "test_email is set to: $test_email"

	if [[ $test_email =~ $email_regex ]]
	then
		echo "THE FORM OF THE INCOMING PARAMETER IS OF A VALID EMAIL ADDRESS"
		test_result=0
	else
		echo "PARAMETER WAS NOT A MATCH FOR OUR KNOWN EMAIL FORM REGEX: "$email_regex"" && sleep 1 && echo
		echo "Returning with a non-zero test result..."
		test_result=1
		return $E_UNEXPECTED_ARG_VALUE
	fi 


	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}
###############################################################################################
function set_working_user_id
{

	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# in order for script to use a variable (user_id) when creating certificate revocation and public key export commands, \
	# we now assign an identifying email address to the global user_id variable:
	# we're doing it here just to make sure we use the same one during interactive key generation:
	
	while true
	do

		user_id=""

		echo && echo "ENTER THE UNIQUE USER-ID (email address) THAT UR ABOUT TO USE FOR KEY GEN:" && echo
		read user_id
		echo && echo "You specified the user-id: $user_id" && echo

		# test user_id for valid email form
		test_email_valid_form "$user_id"
		valid_email_result=$?
		echo " "

		if [ $valid_email_result -eq 0 ]
		then
			echo && echo "EMAIL ADDRESS \"$user_id\" IS VALID"
			#break
		else
			echo && echo "THAT'S NO VALID EMAIL ADDRESS, TRY AGAIN..."
			continue
		fi

		# ensure the user specified email user-id (or substring of it) doesn't already exist in the public keyring
		test_uid_in_pub_keyring "$user_id"
		uid_in_keyring_result=$?
		echo " "
		
		# positive result is bad
		if [ $uid_in_keyring_result -ne 0 ]
		then
			echo && echo "OK TO USE EMAIL ADDRESS \"$user_id\" "
			break
		else
			echo && echo "THAT'S A VALID EMAIL ADDRESS, BUT IT'S ALREADY BEING USED :( TRY AGAIN..."
			continue # just in case we add more code after this block
		fi

	done


	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

}

###############################################################################################
# the act of generating a new key-pair also triggers its' automatic backup, rev. cert generation
# and encryption etc.
function generate_and_manage_keys
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo
	
	
	set_working_user_id

	##############################################
	
	echo && echo "[1] EMAIL ADDRESS USER ID VALIDATION COMPLETE... MOVING ON TO:"
	echo && echo "KEY GENERATION"

	echo && echo "[1] KNOWN DEPENDENCIES: "
	echo "NONE"

	echo && echo "[1] EXISTENCE OF KEY GENERATION DEPENDENCY CONFIRMED OK" && echo
	echo && echo "...WAIT ...YOU'RE ABOUT TO BE ASKED FOR SOME KEY GENERATION PARAMETERS..."	
	sleep 12
	
	generate_public_keypair

	##############################################

	echo && echo "[2] KEY GENERATION COMPLETE... MOVING ON TO:"
	echo && echo "KEYRING BACKUP ACTIVITIES"

	echo && echo "[2] KNOWN DEPENDENCIES: "
	echo "1. KEY GENERATION"

	if [ $new_keygen_OK = true ]
	then
		echo && echo "[2] EXISTENCE OF KEY GENERATION DEPENDENCY CONFIRMED OK" && echo
		echo && echo "...WAIT"	
		sleep 12
	else
		# exit, as nothing further can be done
		echo && echo "ABORTING DUE TO FAILURE OF KEY GENERATION..."
		echo && echo "...WAIT"	
		sleep 4
		exit $E_UNEXPECTED_ARG_VALUE
	fi
	
	backup_public_keyrings

	##############################################

	echo && echo "[3] KEYRING BACKUP ACTIVITIES PRESUMED COMPLETE... MOVING ON TO:"
	echo && echo "REVOCATION CERT. GENERATION"

	echo && echo "[3] KNOWN DEPENDENCIES: "
	echo "1. KEY GENERATION"
	echo "2. user_id"

	if [ $new_keygen_OK = true ]
	then
		echo && echo "[3] EXISTENCE OF KEY GENERATION DEPENDENCY CONFIRMED OK" && echo
		echo && echo "...WAIT"	
		sleep 12
	else
		# exit, as nothing further can be done
		echo && echo "ABORTING DUE TO FAILURE OF KEY GENERATION..."
		echo && echo "...WAIT"	
		sleep 4
		exit $E_UNEXPECTED_ARG_VALUE
	fi

	generate_revocation_certificate

	##############################################

	echo && echo "[4] USER-GENERATED REVOCATION CERT. ACTIVITIES COMPLETE... MOVING ON TO:"
	echo && echo "REVOCATION CERT. ENCRYPTION"

	echo && echo "[4] KNOWN DEPENDENCIES: "
	echo "1. REVOCATION CERT. GENERATION"

	if [ $new_key_rev_cert_OK = true ]
	then
		echo && echo "[4] EXISTENCE OF REVOCATION CERT. GENERATION DEPENDENCY CONFIRMED OK" && echo
		echo && echo "...WAIT"	
		sleep 12
	else
		# exit, as nothing further can be done
		echo && echo "ABORTING DUE TO FAILURE OF REVOCATION CERT. GENERATION..."
		echo && echo "...WAIT ...YOU'RE ABOUT TO BE ASKED FOR SOME ENCRYPTION PARAMETERS..."	
		sleep 4
		exit $E_UNEXPECTED_ARG_VALUE
	fi
	
	encrypt_revocation_certificates

	##############################################

	echo && echo "[5] REVOCATION CERT. ENCRYPTION (INCLUDING SHRED) NOW COMPLETE... MOVING ON TO:"
	echo && echo "REVOCATION CERT. RENAME AND MOVE"

	echo && echo "[5] KNOWN DEPENDENCIES: "
	echo "1. REVOCATION CERT. ENCRYPTION"

	if [ $rev_cert_encrypt_OK = true ]
	then
		echo && echo "[5] EXISTENCE OF REVOCATION CERT. ENCRYPTION DEPENDENCY CONFIRMED OK" && echo
		echo && echo "...WAIT"	
		sleep 12
	else
		# exit, as nothing further can be done
		echo && echo "ABORTING DUE TO FAILURE OF REVOCATION CERT. ENCRYPTION..."
		echo && echo "...WAIT"	
		sleep 4
		exit $E_UNEXPECTED_ARG_VALUE
	fi

	rename_and_move_revocation_certificates

	##############################################

	echo && echo "[6] REVOCATION CERT. RENAME AND MOVE NOW COMPLETE... MOVING ON TO:"
	echo && echo "PUBLIC KEYS EXPORT"

	echo && echo "[6] KNOWN DEPENDENCIES: "
	echo "1. KEY GENERATION"
	echo "2. user_id"

	if [ $new_keygen_OK = true ]
	then
		echo && echo "[6] EXISTENCE OF KEY GENERATION DEPENDENCY CONFIRMED OK" && echo
		echo && echo "...WAIT"	
		sleep 12
	else
		# exit, as nothing further can be done
		echo && echo "ABORTING DUE TO FAILURE OF KEY GENERATION"
		echo && echo "...WAIT"	
		sleep 4
		exit $E_UNEXPECTED_ARG_VALUE
	fi

	export_public_keys

	##############################################

	echo && echo "[7] PUBLIC KEYS EXPORT NOW COMPLETE... MOVING ON TO:"
	echo && echo "FINISHING..."

	echo && echo "[7] KNOWN DEPENDENCIES: "
	echo "1. PUBLIC KEYS EXPORT"

	if [ $public_key_export_OK = true ]
	then
		echo && echo "[7] EXISTENCE OF PUBLIC KEYS EXPORT CONFIRMED OK" && echo
		echo && echo "...WAIT"	
		sleep 12
	else
		# exit, as nothing further can be done
		echo && echo "ABORTING DUE TO FAILURE OF PUBLIC KEYS EXPORT"
		echo && echo "...WAIT"	
		sleep 4
		exit $E_UNEXPECTED_ARG_VALUE
	fi

	echo && echo "[7] WE'VE NOW COMPLETED THE WHOLE PROCESS OF KEY GENERATION AND MANAGEMENT...WAIT" && echo
	sleep 4

	##############################################


	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo
}

###############################################################################################
###############################################################################################
################################################################################################
################################################################################################

# check that the OpenPGP tool gpg is installed on the system
# check that the file-encrypter.sh program is accessible
function check_encryption_platform
{
		
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	bash -c "which gpg 2>/dev/null" # suppress stderr (but not stdout for now)
	if [ $? -eq 0 ]
	then
		echo "OpenPGP PROGRAM INSTALLED ON THIS SYSTEM OK"
	else
		echo "FAILED TO FIND THE REQUIRED OpenPGP PROGRAM"
		# -> exit due to failure of any of the above tests:
		echo "Exiting from function \"${FUNCNAME[0]}\" in script $(basename $0)"
		exit $E_REQUIRED_PROGRAM_NOT_FOUND
	fi

	# we test for the existence of a known script that provides encryption services:
	which file-encrypter.sh
	if [ $? -eq 0 ]
	then
		echo "THE file-encrypter.sh PROGRAM WAS FOUND TO BE INSTALLED OK ON THIS HOST SYSTEM"	
	else
		echo "FAILED TO FIND THE file-encrypter.sh PROGRAM ON THIS SYSTEM, SO NO NOTHING LEFT TO DO BUT EXEET, GOODBYE"
		exit $E_REQUIRED_PROGRAM_NOT_FOUND
	fi	

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

}

#########################################################################################################
##########################################################################################################
# keep sanitise functions separate and specialised, as we may add more to specific value types in future
# FINAL OPERATION ON VALUE, SO GLOBAL test_line SET HERE. RENAME CONCEPTUALLY DIFFERENT test_line NAMESAKES
function sanitise_absolute_path_value ##
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# sanitise values
	# - trim leading and trailing space characters
	# - trim trailing / for all paths
	test_line="${1}"
	echo "test line on entering "${FUNCNAME[0]}" is: $test_line" && echo

	while [[ "$test_line" == *'/' ]] ||\
	 [[ "$test_line" == *[[:blank:]] ]] ||\
	 [[ "$test_line" == [[:blank:]]* ]]
	do 
		# TRIM TRAILING AND LEADING SPACES AND TABS
		# backstop code, as with leading spaces, config file line wouldn't even have been
		# recognised as a value!
		test_line=${test_line%%[[:blank:]]}
		test_line=${test_line##[[:blank:]]}

		# TRIM TRAILING / FOR ABSOLUTE PATHS:
		test_line=${test_line%'/'}
	done

	echo "test line after trim cleanups in "${FUNCNAME[0]}" is: $test_line" && echo

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo
}

##########################################################################################################
# A DUAL PURPOSE FUNCTION - CALLED TO EITHER TEST OR TO SET LINE TYPES:
# TESTS WHETHER THE LINE IS OF EITHER VALID comment, empty/blank OR string (variable or value) TYPE,
# SETS THE GLOBAL line_type AND test_line variableS.
function test_and_set_line_type
{
	#echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	# TODO: ADD ANOTHER CONFIG FILE VALIDATION TEST:
	# TEST THAT THE LINE FOLLOWING A VARIABLE= ALPHANUM STRING MUST BE A VALUE/ ALPHANUM STRING, ELSE FAIL
	test_line="${1}"
	line_type=""

	if [[ "$test_line" == "#"* ]] # line is a comment (OR *"#"* in case space char before the # ? - try it)
	then
		line_type="comment"
		#echo "line_type set to: $line_type"
	elif [[ "$test_line" =~ [[:blank:]] || "$test_line" == "" ]] # line empty or contains only spaces or tab characters
	then
		line_type="empty"
		#echo "line_type set to: $line_type"
	elif [[ "$test_line" =~ [[:alnum:]] ]] # line is a string (not commented)
	then
		echo -n "Alphanumeric string  :  "
		if [[ "$test_line" == *"=" ]]
		then
			line_type="variable_string"
			echo "line_type set to: "$line_type" for "$test_line""
		elif [[ "$test_line" =~ $all_filepath_regex ]]	#
		then
			line_type="value_string"
			echo "line_type set to: "$line_type" for "$test_line""
		else
            echo "line_type set to: \"UNKNOWN\" for "${test_line}""
			echo "Failsafe : Couldn't match the Alphanum string"
			return $E_UNEXPECTED_BRANCH_ENTERED
		fi
	else
	    echo "line_type set to: \"UNKNOWN\" for "$test_line""
		echo "Failsafe : Couldn't match this line with ANY line type!"
		return $E_UNEXPECTED_BRANCH_ENTERED
	fi

	#echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

}
##########################################################################################################
# for any absolute file path value to be imported...
function get_config_values_for_all_dirs
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	for keyword in "synchronised_location_holding_dir_fullpath=" "public_keyring_default_directory_fullpath="\
	"revocation_certificate_default_directory_fullpath="
	do
		line_type=""
		value_collection="OFF"

		while read lineIn
		do
			test_and_set_line_type "$lineIn" # interesting for the line FOLLOWING that keyword find

			if [[ $value_collection == "ON" && $line_type == "value_string" ]]
			then
				sanitise_absolute_path_value "$lineIn"
				echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
				echo "test_line has the value: $test_line"
				echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
				set -- $test_line # using 'set' to get test_line out of this subprocess into a positional parameter ($1)

			elif [[ $value_collection == "ON" && $line_type != "value_string" ]]
			# last value has been collected for this holding directory
			then
				value_collection="OFF" # just because..
				break # end this while loop, as last value has been collected for this holding directory
			else
				# value collection must be OFF
				:
			fi			
			
			# switch value collection ON for the NEXT line read
			# THEREFORE WE'RE ASSUMING THAT A KEYWORD CANNOT EXIST ON THE 1ST LINE OF THE FILE
			if [[ "$lineIn" == "$keyword" ]]
			then
				value_collection="ON"
			fi

		done < "$config_file_fullpath"

		# ASSIGN
		echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
		echo "test_line has the value: $1"
		echo "the keyword on this for-loop is set to: $keyword"
		echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"

		if [ "$keyword" == "synchronised_location_holding_dir_fullpath=" ]
		then
			synchronised_location_holding_dir_fullpath="$1"
			# test_line just set globally in sanitise_absolute_path_value function
		elif [ "$keyword" == "public_keyring_default_directory_fullpath=" ]
		then
			public_keyring_default_directory_fullpath="$1"
			# test_line just set globally in sanitise_absolute_path_value function
		elif [ "$keyword" == "revocation_certificate_default_directory_fullpath=" ]
		then
			revocation_certificate_default_directory_fullpath="$1"
			# test_line just set globally in sanitise_absolute_path_value function
		else
			echo "Failsafe branch entered"
			exit $E_UNEXPECTED_BRANCH_ENTERED
		fi

		set -- # unset that positional parameter we used to get test_line out of that while read subprocess
		echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
		echo "test_line (AFTER set --) has the value: $1"
		echo "@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"

	done

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

}

##########################################################################################################
##########################################################################################################

# firstly, we test that the parameter we got is of the correct form for an absolute file | sanitised directory path 
# if this test fails, there's no point doing anything further
# 
function test_file_path_valid_form
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_file_fullpath=$1
	
	echo "test_file_fullpath is set to: $test_file_fullpath"
	#echo "test_dir_fullpath is set to: $test_dir_fullpath"

	if [[ $test_file_fullpath =~ $abs_filepath_regex ]]
	then
		echo "THE FORM OF THE INCOMING PARAMETER IS OF A VALID ABSOLUTE FILE PATH"
		test_result=0
	else
		echo "PARAMETER WAS NOT A MATCH FOR OUR KNOWN PATH FORM REGEX: "$abs_filepath_regex"" && sleep 1 && echo
		echo "Returning with a non-zero test result..."
		test_result=1
		return $E_UNEXPECTED_ARG_VALUE
	fi 


	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}

###############################################################################################
# test for read access to file 
# 
function test_file_path_access
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_file_fullpath=$1

	echo "test_file_fullpath is set to: $test_file_fullpath"

	# test for expected file type (regular) and read permission
	if [ -f "$test_file_fullpath" ] && [ -r "$test_file_fullpath" ]
	then
		# test file found and accessible
		echo "Test file found to be readable" && echo
		test_result=0
	else
		# -> return due to failure of any of the above tests:
		test_result=1 # just because...
		echo "Returning from function \"${FUNCNAME[0]}\" with test result code: $E_REQUIRED_FILE_NOT_FOUND"
		return $E_REQUIRED_FILE_NOT_FOUND
	fi

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}
###############################################################################################
# test for access to the file holding directory
# # TODO: DO WE NEED ANOTHER TEST FOR PERMISSION TO WRITE TO DIRECTORY?
function test_dir_path_access
{
	echo && echo "ENTERED INTO FUNCTION ${FUNCNAME[0]}" && echo

	test_result=
	test_dir_fullpath=$1

	echo "test_dir_fullpath is set to: $test_dir_fullpath"

	if [ -d "$test_dir_fullpath" ] && cd "$test_dir_fullpath" 2>/dev/null
	then
		# directory file found and accessible
		echo "directory "$test_dir_fullpath" found and accessed ok" && echo
		test_result=0
	else
		# -> return due to failure of any of the above tests:
		test_result=1
		echo "Returning from function \"${FUNCNAME[0]}\" with test result code: $E_REQUIRED_FILE_NOT_FOUND"
		return $E_REQUIRED_FILE_NOT_FOUND
	fi

	echo && echo "LEAVING FROM FUNCTION ${FUNCNAME[0]}" && echo

	return "$test_result"
}
#########################################################################################################

main "$@"; exit


# TODO:
# CREATE AND PUSH FLOWCHART ALGORITHM FOR COMMAND GENERATION FUNCTIONS (AN IGNORE FILE)
# CREATE CONFIGURATION IMPORT FUNCTIONS
# CALL SEPARATE SCRIPT FOR EACH DISTINCT SERVICE
# CREATE THE PUBLIC-KEY BACKUP FUNCTIONALITY SCRIPT

# UPDATE THE README.md TO ADD A PRE-REQUISITES SECTION

# UPDATE TO USE OF OPTION SELECTION FUNCTION IF APPROPRIATE


# .. don't forget to unset when returning to calling program

###############################################################################################

## USE CASE - CALLED BY audit-list-maker.sh TO GPG ENCRYPT A SINGLE FILE

# FOR ENCRYPTION OF A SINGLE FILE, ALL es EVER NEEDS TO BE PASSED AS A PARAMETER IS THE ABSOLUTE PATH FILENAME OF THE 
# PLAINTEXT FILE. IT CAN GET EVERYTHING ELSE IT NEEDS EITHER FROM CONFIGURATION FILE DEFAULTS, OR FROM THE USER.
#

# decides whether being called directly or by another script

# takes in, validates and assigns the plaintext filename parameter

# tests its environment - config files, `which gpg`, public key-pair pre-generated...


# gets  and validates any unknown required parameters from the user - sender, recipient UID (based on `hostname`) \
#  if using public key encryption - ANY DEFAULTS FOR THIS COULD BE IN A CONFIGURATION FILE FOR THIS PROGRAM
	# - cryptographic system to be used (whether public key or symmetric key crypto)
	# - the output format whether the binary default for gpg or ascii armoured
	# - the desired output filename for the encrypted file (full path): [DEFAULT = SAME AS INPUT WITH .asc|.pgp]

# if all good, es shows user the command it wants to execute
# $ gpg --armor --output "$plaintext_file_fullpath.asc" --local-user <uid> recipient <uid> --encrypt "$plaintext_file_fullpath"

# if user give ok, es executes the command(s)

# es tests resulting postconditions#

# es reports success to user and returns control

###############################################################################################


#ssh hostname ## this command likely to be read in from file

## definitely control the hosts on which this program can run
#
# hostname will determine which ssh code runs
#

###############################################################################################

# these files need to be backed up and encrypted:
#public keyrings such as:
#~/.gnupg/pubring.gpg 
#~/.gnupg/pubring.kbx
#
#these revocation certs need to be CIA stored, so backup and encryption as well as on separate media
#~/.gnupg/opengpg_revocs.d/
#
#integration with existing system may look like:
#- an option to run this script post-shred an pre-mutables synchronisation

###############################################################################################

# tests whether parameter in of type array, if true returns 0, else returns 1
# declare -a ## returns list of all the current array variables
# grepping with our array works, but not 100% clear on mechanism...	
# TODO: TURN THIS INTO A GENERAL PURPOSE type_array_test FUNCTION IF IT IS NEEDED AGAIN
#declare -a | grep "${incoming_parameter}" 2> /dev/null ##
#if [ $? -eq 0 ]
#then
#	echo "THE INCOMING PARAMETER WAS OF TYPE ARRAY"
#	incoming_array=("${incoming_parameter[@]}")
#else
#	echo "The incoming parameter was NOT of type ARRAY"
#fi
#
#echo ${incoming_parameter[@]}
#
## test whether incoming parameter is of type string
#
#
#
#for ((index=0; index<$number_of_incoming_params; index++));
#	do	
#		position=$((index + 1))
#		echo "position is set to: $position"
#		incoming_array[$index]=${postition}
#	done