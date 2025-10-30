
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-3ginfo-mod
LUCI_TITLE:=LuCI JS Support for 3ginfo-mod
MAINTAINER:=Anggun Caksono <anggun@cakson.my.id>
LUCI_DESCRIPTION:=LuCI JS interface for the 3ginfo-mod. The package allows you to view the parameters of the mobile internet connection.
LUCI_DEPENDS:=+sms-tool +comgt +kmod-usb-serial-option
LUCI_PKGARCH:=all
PKG_VERSION:=1.0.81
PKG_RELEASE:=20251030

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
