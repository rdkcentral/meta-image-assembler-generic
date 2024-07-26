# Generic rootfs_postprocess functions

create_init_link() {
        ln -sf /sbin/init ${IMAGE_ROOTFS}/init
}

ROOTFS_POSTPROCESS_COMMAND += "create_init_link; "

ROOTFS_POSTPROCESS_COMMAND += "wpeframework_binding_patch; "

wpeframework_binding_patch(){
    sed -i "s/127.0.0.1/0.0.0.0/g" ${IMAGE_ROOTFS}/etc/WPEFramework/config.json
}

# /meta-rdk-video/recipes-core/images/middleware-%.bbappend
# Turn off autostart if launching from systemd
ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES', 'thunder_startup_services', 'thunder_services_autostart_patch; ','',d)}"

thunder_services_autostart_patch() {
   find  ${IMAGE_ROOTFS}/etc/WPEFramework/plugins/ -type f | xargs sed -i -r 's/"autostart"[[:space:]]*:[[:space:]]*true/"autostart":false/g'
}

#/meta-rdk/classes/rdke-image.bbclass 
IMAGE_FEATURES[validitems] += " nightly tdk"

IMAGE_FEATURES += "read-only-rootfs"
IMAGE_EXTN =  "${@d.getVar("YOCTO_IMAGE_NAME_SUFFIX", True) or ""}"
IMAGE_NAME = "${MACHINE_IMAGE_NAME}${@bb.utils.contains("IMAGE_FEATURES", "tdk", "_TDK", "", d)}_${PROJECT_BRANCH}_${DATETIME}${IMAGE_EXTN}${@bb.utils.contains("IMAGE_FEATURES", "nightly", "_NG", "", d)}"

ROOTFS_POSTPROCESS_COMMAND += '${@bb.utils.contains("IMAGE_FEATURES", "read-only-rootfs", "rdk_read_only_rootfs_hook; ", "",d)}'
IMAGE_NAME[vardepsexclude] += "TIME DATE DATETIME"
rdk_read_only_rootfs_hook () {
}

R = "${IMAGE_ROOTFS}"

PROJECT_BRANCH ?= "default"

python version_hook(){
    bb.build.exec_func('create_version_file', d)
}

python create_version_file() {

    version_file = os.path.join(d.getVar("R", True), 'version.txt')
    image_name = d.getVar("IMAGE_NAME", True)
    machine = d.getVar("MACHINE", True).upper()
    branch = d.getVar("PROJECT_BRANCH", True)
    yocto_version = d.getVar("DISTRO_CODENAME", True)
    release_version = d.getVar("RELEASE_VERSION", True) or '0.0.0.0'
    release_spin = d.getVar("RELEASE_SPIN", True) or '0'
    stamp = d.getVar("DATETIME", True)
    t = time.strptime(stamp, '%Y%m%d%H%M%S')
    build_time = time.strftime('"%Y-%m-%d %H:%M:%S"', t)
    gen_time = time.strftime('Generated on %a %b %d  %H:%M:%S UTC %Y', t)
    extra_versions_path = d.getVar("EXTRA_VERSIONS_PATH", True)
    extra_version_files = []
    for (dirpath, dirnames, filenames) in os.walk(extra_versions_path):
        extra_version_files.extend(sorted(filenames))
        break
    extra_versions = []
    for filename in extra_version_files:
        with open(os.path.join(extra_versions_path, filename)) as fd:
            for line in fd.readlines():
                extra_versions.append(line)
    with open(version_file, 'w') as fw:
        fw.write('imagename:{0}\n'.format(image_name))
        fw.write('BRANCH={0}\n'.format(branch))
        fw.write('YOCTO_VERSION={0}\n'.format(yocto_version))
        fw.write('VERSION={0}\n'.format(release_version))
        fw.write('SPIN={0}\n'.format(release_spin))
        fw.write('BUILD_TIME={0}\n'.format(build_time))
        for version_string in extra_versions:
            fw.write("{0}\n".format(version_string.strip('\n')))
        fw.write('{0}\n'.format(gen_time))
    build_config = os.path.join(d.getVar("TOPDIR", True), 'build-images.txt')
    taskdata = d.getVar("BB_TASKDEPDATA", True)
    key = sorted(taskdata)[0]
    target = taskdata[key][0]
    line = '{0} - {1}\n'.format(target, image_name)
    with open(build_config, 'a') as fw:
        fw.write(line)
}

create_version_file[vardepsexclude] += "DATETIME"
create_version_file[vardepsexclude] += "BB_TASKDEPDATA"

ROOTFS_POSTPROCESS_COMMAND += 'version_hook; '

inherit core-image

# /meta-rdk/recipes-core/images/syslog-ng-config.inc
ROOTFS_POSTPROCESS_COMMAND += "${@bb.utils.contains('DISTRO_FEATURES','syslog-ng',' generate_syslog_ng_config; ',' ',d)}"

LOG_PATH_hybrid = "/opt/logs"
LOG_PATH_client = "/opt/logs"
LOG_PATH_broadband = "/rdklogs/logs"

python generate_syslog_ng_config() {
    bb.build.exec_func('create_metadata_file',d)
    bb.build.exec_func('update_constants',d)
    bb.build.exec_func('update_filters',d)
    bb.build.exec_func('update_destination',d)
    bb.build.exec_func('update_log',d)
    bb.build.exec_func('update_properties',d)
    bb.build.exec_func('clear_tmp_files',d)
}

create_metadata_file() {
    syslog_ng_dir="${IMAGE_ROOTFS}/${sysconfdir}/syslog-ng/"
    filter_dir="$syslog_ng_dir/filter/"
    metadata_dir="$syslog_ng_dir/metadata/"
    device_properties_file="${IMAGE_ROOTFS}/${sysconfdir}/device.properties"

    for file in `find $metadata_dir -type f`
    do
        cat $file >> $metadata_dir/metadata_tmp.conf
    done
    for file in `find $filter_dir -type f`
    do
        cat $file >> $filter_dir/filter_tmp.conf
    done
    awk '!duplicate[$0]++' $filter_dir/filter_tmp.conf > $filter_dir/filter_file.conf
    awk '!duplicate[$0]++' $metadata_dir/metadata_tmp.conf > $metadata_dir/metadata.conf

    #dobby logs should be stored in wpeframework.log incase of placto/hisence/RDKV devices whereas in sky devices it should be stored in sky-messages.log file.
    dobby_enabled="DOBBY_ENABLED=true"
    sky_epg_support_enabled="SKY_EPG_SUPPORT=true"
    if grep "$dobby_enabled" $device_properties_file; then
        echo "SYSLOG-NG_SERVICE_wpeframework = dobby.service" >> $metadata_dir/metadata.conf
    elif grep "$sky_epg_support_enabled" $device_properties_file; then
        echo "SYSLOG-NG_SERVICE_sky-messages = dobby.service" >> $metadata_dir/metadata.conf
    fi
}

python update_constants () {

    import os
    config_dir = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/"
    config_file = config_dir + "syslog-ng.conf"
    version_file = config_dir + ".version"
    log_path = d.getVar('LOG_PATH', True)
    with open(version_file, 'r') as config_version:
        get_version = config_version.readline()
        syslogng_version = ".".join(get_version.split(".")[:2])
        config_version.close()
    if not os.path.exists(config_dir):
        os.makedirs(config_dir)
    with open(config_file, 'w') as conf:
        conf.write("@version: %s\n" % (syslogng_version))
        conf.write("# Syslog-ng configuration file, created by syslog-ng configuration generator\n")
        conf.write("\n# First, set some global options.\n")
        conf.write("options { flush_lines(0);owner(\"root\"); perm(0664); stats_freq(0);use-dns(no);dns-cache(no);time-zone(\"Etc/UTC\"); };\n")
        conf.write("\n@define log_path \"%s\"\n" % (log_path))
        conf.write("\n########################\n")
        conf.write("# Sources\n")
        conf.write("########################\n")
        conf.write("\n#systemd journal entries\n")
        conf.write("source s_journald { systemd-journal(prefix(\".SDATA.journald.\")); };\n")
        conf.write("\n########################\n")
        conf.write("# Templates\n")
        conf.write("########################\n")
        conf.write("#Template for RDK logging\n")
        conf.write("template-function t_rdk \"${S_YEAR}-${S_MONTH}-${S_DAY}T${S_HOUR}:${S_MIN}:${S_SEC}.${S_MSEC}Z ${MSGHDR} ${MSG}\";\n")
        conf.write("#Template to print only MESSAGE\n")
        conf.write("template-function t_files \"${MSGHDR} ${MSG}\";\n")
        conf.close()
}

python update_filters() {

    filter_list = []
    import os
    config_dir = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/"
    config_file = config_dir + "syslog-ng.conf"
    filter_file = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/filter/filter_file.conf"
    metadata_file = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/metadata/metadata.conf"
    with open(config_file, 'a') as conf:
        conf.write("\n########################\n")
        conf.write("# Filters\n")
        conf.write("########################\n")
        conf.write("# With these rules, we can set which message go where.\n\n")
        conf.close()
    with open(filter_file, 'r') as filterdata:
        file_lines = filterdata.readlines()
        for lines in file_lines:
            line = lines.strip()
            service_tag = 'SYSLOG-NG_SERVICE_' + line + " ="
            program_tag = 'SYSLOG-NG_PROGRAM_' + line + " ="
            with open(metadata_file, 'r') as metadata:
                meta_lines = metadata.readlines()
                service_filter_list = [ service for service in meta_lines if service_tag in service ]
                program_filter_list = [ program for program in meta_lines if program_tag in program ]
                program_filter = ""
                service_filter = ""
                if program_filter_list:
                    program_filter = " \"${PROGRAM}\" eq " + "\"" + program_filter_list[0].rsplit("=", 1)[1].strip() + "\""
                if len(service_filter_list) >= 1:
                    for serv in service_filter_list:
                        service_filter = service_filter + " \"${.SDATA.journald._SYSTEMD_UNIT}\" eq " + "\"" + serv.rsplit("=", 1)[1].strip() + "\""
                        if (not serv is service_filter_list[-1]) or (program_filter_list):
                            service_filter = service_filter + " or"

                if program_filter or service_filter:
                    filter_statement = "filter f_" + line + " {" + service_filter + program_filter + " };"
                    with open(config_file, 'a') as conf:
                        conf.write("%s\n" % (filter_statement))
                        conf.close()
                metadata.close()
        filterdata.close()
}


python update_destination() {

    destination = []
    filter_list = []
    import os
    config_dir = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/"
    config_file = config_dir + "syslog-ng.conf"
    filter_file = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/filter/filter_file.conf"
    metadata_file = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/metadata/metadata.conf"
    with open(config_file, 'a') as conf:
        conf.write("\n########################\n")
        conf.write("# Destination\n")
        conf.write("########################\n")
        conf.write("# Set the destination path.\n\n")
        conf.close()
    with open(filter_file, 'r') as filterdata:
        file_lines = filterdata.readlines()
        for lines in file_lines:
            line = lines.strip()
            destination_tag = 'SYSLOG-NG_DESTINATION_' + line + " ="
            with open(metadata_file, 'r') as metadata:
                meta_lines = metadata.readlines()
                destination_filter_list = [ service for service in meta_lines if destination_tag in service ]
                if len(destination_filter_list) == 0 or destination_filter_list[0].rsplit("=", 1)[1].strip() == "" :
                    metadata.close()
                    continue
                destination_statement = "destination d_" + line + " { file(\"`log_path`/" + destination_filter_list[0].rsplit("=", 1)[1].strip() + "\" template(\"$(t_rdk)\\n\"));};"
                with open(config_file, 'a') as conf:
                    conf.write("%s\n" % (destination_statement))
                    conf.close()
                metadata.close()
        filterdata.close()
    with open(config_file, 'a') as conf:
        conf.write("#Fallback log destination\n")
        conf.write("destination d_fallback { file(\"`log_path`/syslog_fallback.log\" template(\"$(t_rdk)\\n\"));};\n")
        conf.close()
}

python update_log() {
    filter_list = []
    import os
    config_dir = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/"
    config_file = config_dir + "syslog-ng.conf"
    filter_file = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/filter/filter_file.conf"
    metadata_file = d.getVar('IMAGE_ROOTFS', True) + d.getVar('sysconfdir', True)  + "/syslog-ng/metadata/metadata.conf"
    with open(config_file, 'a') as conf:
        conf.write("\n########################\n")
        conf.write("# Logs\n")
        conf.write("########################\n")
        conf.write("# Log statements are processed in the order they appear in the configuration file.\n\n")
        conf.write("#sslendpoint logging based on identifier\n")
        conf.write("log { source(s_journald); filter(f_sslendpoint); destination(d_sslendpoint); flags(final); };\n\n")
        conf.close()
    with open(filter_file, 'r') as filterdata:
        file_lines = filterdata.readlines()
        for lines in file_lines:
            filter = lines.strip()
            lograte_tag = 'SYSLOG-NG_LOGRATE_' + filter
            destination_tag = 'SYSLOG-NG_DESTINATION_' + filter
            lograte_frequent = lograte_tag + " = very-high"
            with open(metadata_file, 'r') as metadata:
                if destination_tag in metadata.read():
                    destination_tag = "destination(d_" + filter + "); "
                else:
                    destination_tag = ""
                metadata.seek(0)
                if lograte_frequent in metadata.read():
                    filter_tag = "filter(f_" + filter + "); "
                    log_statement = "log { source(s_journald); " + filter_tag +  destination_tag + "flags(final); };"
                    with open(config_file, 'a') as conf:
                        conf.write("%s\n" % (log_statement))
                        conf.close()
                    metadata.close()
        for lines in file_lines:
            filter = lines.strip()
            lograte_tag = 'SYSLOG-NG_LOGRATE_' + filter
            destination_tag = 'SYSLOG-NG_DESTINATION_' + filter
            lograte_regular = lograte_tag + " = high"
            with open(metadata_file, 'r') as metadata:
                if destination_tag in metadata.read():
                    destination_tag = "destination(d_" + filter + "); "
                else:
                    destination_tag = ""
                metadata.seek(0)
                if lograte_regular in metadata.read():
                    filter_tag = "filter(f_" + filter + "); "
                    log_statement = "log { source(s_journald); " + filter_tag +  destination_tag + "flags(final); };"
                    with open(config_file, 'a') as conf:
                        conf.write("%s\n" % (log_statement))
                        conf.close()
                metadata.close()
        for lines in file_lines:
            filter = lines.strip()
            lograte_tag = 'SYSLOG-NG_LOGRATE_' + filter
            destination_tag = 'SYSLOG-NG_DESTINATION_' + filter
            lograte_occasional = lograte_tag + " = medium"
            with open(metadata_file, 'r') as metadata:
                if destination_tag in metadata.read():
                    destination_tag = "destination(d_" + filter + "); "
                else:
                    destination_tag = ""
                metadata.seek(0)
                if lograte_occasional in metadata.read():
                    filter_tag = "filter(f_" + filter + "); "
                    log_statement = "log { source(s_journald); " + filter_tag +  destination_tag + "flags(final); };"
                    with open(config_file, 'a') as conf:
                        conf.write("%s\n" % (log_statement))
                        conf.close()
                metadata.close()
        for lines in file_lines:
            filter = lines.strip()
            lograte_tag = 'SYSLOG-NG_LOGRATE_' + filter
            destination_tag = 'SYSLOG-NG_DESTINATION_' + filter
            lograte_only_once = lograte_tag + " = low"
            with open(metadata_file, 'r') as metadata:
                if destination_tag in metadata.read():
                    destination_tag = "destination(d_" + filter + "); "
                else:
                    destination_tag = ""
                metadata.seek(0)
                if lograte_only_once in metadata.read():
                    filter_tag = "filter(f_" + filter + "); "
                    log_statement = "log { source(s_journald); " + filter_tag +  destination_tag + "flags(final); };"
                    with open(config_file, 'a') as conf:
                        conf.write("%s\n" % (log_statement))
                        conf.close()
                    metadata.close()
        filterdata.close()
    with open(config_file, 'a') as conf:
        conf.write("log { source(s_journald); destination(d_fallback); flags(fallback); };\n")
        conf.close()

}

clear_tmp_files () {
    filter_dir="${IMAGE_ROOTFS}/${sysconfdir}/syslog-ng/filter"
    metadata_dir="${IMAGE_ROOTFS}/${sysconfdir}/syslog-ng/metadata"

    rm -rf ${filter_dir}
    rm -rf ${metadata_dir}
}

update_properties () {
    device_properties_file="${IMAGE_ROOTFS}/${sysconfdir}/device.properties"

    echo "SYSLOG_NG_ENABLED=true" >> $device_properties_file
}
