Name: harbour-fivinarow
Version: 1.0.0
Release: 1
Summary: Five in a Row (Gomoku)
License: MIT
URL: https://example.com/harbour-fivinarow
Source0: %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-root

Requires:       sailfishsilica-qt5
BuildRequires:  pkgconfig(sailfishapp)
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(packagekitqt5)
BuildRequires:  desktop-file-utils

%description
Five in a Row — lightweight Gomoku game ported to Sailfish OS.

%prep
%setup -q

%build
mkdir -p build
cd build
cmake ../sailfish
make -j$(nproc)

%install
rm -rf %{buildroot}

# ----------------------------
# Install binary
# ----------------------------
mkdir -p %{buildroot}/usr/bin
install -m 755 build/harbour-fivinarow %{buildroot}/usr/bin/

# ----------------------------
# Install QML files under qml/
# SailfishApp expects: /usr/share/<appname>/qml/harbour-fivinarow.qml
# ----------------------------
mkdir -p %{buildroot}/usr/share/%{name}/qml
cp -a sailfish/*.qml %{buildroot}/usr/share/%{name}/qml/
cp -a sailfish/*.js %{buildroot}/usr/share/%{name}/qml/ 2>/dev/null || true

# Copy icons into QML folder (optional, for relative paths)
#cp -a sailfish/icons %{buildroot}/usr/share/%{name}/qml/

# ----------------------------
# Install desktop file
# ----------------------------
mkdir -p %{buildroot}/usr/share/applications
install -m 644 sailfish/desktop/%{name}.desktop \
    %{buildroot}/usr/share/applications/%{name}.desktop

# ----------------------------
# Install icons into proper icon theme directories
# ----------------------------
mkdir -p %{buildroot}/usr/share/icons/hicolor/172x172/apps

install -m 644 sailfish/icons/icon-172.png \
    %{buildroot}/usr/share/icons/hicolor/172x172/apps/%{name}.png

# ----------------------------
# Install documentation
# ----------------------------
mkdir -p %{buildroot}/usr/share/doc/%{name}
cp README_Sailfish.md \
    %{buildroot}/usr/share/doc/%{name}

%files
%defattr(-,root,root,-)
/usr/bin/%{name}
/usr/share/%{name}
/usr/share/icons/hicolor/172x172/apps/%{name}.png
/usr/share/applications/%{name}.desktop
/usr/share/doc/%{name}

%changelog
* Fri Dec 12 2025 edp17 - 1.0.0-1
- Initial package