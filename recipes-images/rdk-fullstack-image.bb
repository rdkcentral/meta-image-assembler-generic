SUMMARY = "RDK Full Stack image"

LICENSE = "MIT"
IMAGE_INSTALL = " \
                 packagegroup-foundation-layer \
                 packagegroup-vendor-layer \
                 packagegroup-middleware-generic \
                 packagegroup-application-layer \
                 "
inherit core-image

inherit custom-rootfs-configuration

IMAGE_ROOTFS_SIZE ?= "8192"
IMAGE_ROOTFS_EXTRA_SPACE_append = "${@bb.utils.contains("DISTRO_FEATURES", "systemd", " + 4096", "" ,d)}"

# Community specific rootfs_postprocess func

ROOTFS_POSTPROCESS_COMMAND += "update_dropbearkey_path; "
update_dropbearkey_path() {
   if [ -f "${IMAGE_ROOTFS}/lib/systemd/system/dropbearkey.service" ]; then
        sed -i 's/\/etc\/dropbear/\/opt\/dropbear/g' ${IMAGE_ROOTFS}/lib/systemd/system/dropbearkey.service
   fi
}

# RDK-50713: Remove securemount dependency from wpa_supplicant.service
# Revert once the actual fix is merged as part of the ticket
ROOTFS_POSTPROCESS_COMMAND += "remove_securemount_dep_patch;"

remove_securemount_dep_patch() {
   sed -i '/Requires=securemount.service/d' ${IMAGE_ROOTFS}/lib/systemd/system/wpa_supplicant.service
   sed -i 's/\bsecuremount\.service\b//g' ${IMAGE_ROOTFS}/lib/systemd/system/wpa_supplicant.service
}
