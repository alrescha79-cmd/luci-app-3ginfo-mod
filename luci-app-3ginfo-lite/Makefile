
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-3ginfo-mod
LUCI_TITLE:=LuCI JS Support for 3ginfo-mod
MAINTAINER:=Anggun Caksono <anggun@cakson.my.id>
LUCI_DESCRIPTION:=LuCI JS interface for the 3ginfo-mod. The package allows you to view the parameters of the mobile internet connection.
LUCI_DEPENDS:=+sms-tool +comgt +kmod-usb-serial-option
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.9
PKG_RELEASE:=20251031

# Preserve config files during upgrade
PKG_CONFIG_DEPENDS:=CONFIG_PACKAGE_$(PKG_NAME)

define Package/$(PKG_NAME)/conffiles
/etc/config/3ginfo
/etc/config/modemdefine
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
