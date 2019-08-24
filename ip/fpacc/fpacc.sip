set_global_assignment -entity "fpacc" -library "lib_fpacc" -name IP_TOOL_NAME "altera_fp_acc_custom"
set_global_assignment -entity "fpacc" -library "lib_fpacc" -name IP_TOOL_VERSION "18.0"
set_global_assignment -entity "fpacc" -library "lib_fpacc" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_fpacc" -name SPD_FILE [file join $::quartus(sip_path) "fpacc.spd"]

set_global_assignment -library "lib_fpacc" -name MISC_FILE [file join $::quartus(sip_path) "fpacc_sim/dspba_library_package.vhd"]
set_global_assignment -library "lib_fpacc" -name MISC_FILE [file join $::quartus(sip_path) "fpacc_sim/dspba_library.vhd"]
set_global_assignment -library "lib_fpacc" -name MISC_FILE [file join $::quartus(sip_path) "fpacc_sim/fpacc.vhd"]
