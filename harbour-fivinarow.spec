Name: harbour-fivinarow
Version: 1.2.0
Release: 0.7.0
Summary: Five in a Row (Gomoku)
License: GPL-3.0-or-later
URL: https://github.com/edp17/harbour-fivinarow
Source0: %{name}-%{version}.tar.gz
BuildRoot: %{_tmppath}/%{name}-%{version}-root

Requires:       sailfishsilica-qt5
BuildRequires:  pkgconfig(sailfishapp)
BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Concurrent)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  qt5-qttools-linguist
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

# ----------------------------
# Install translations
# ----------------------------
mkdir -p %{buildroot}/usr/share/%{name}/translations
install -m 644 build/harbour-fivinarow-hu.qm \
    %{buildroot}/usr/share/%{name}/translations/

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
* Fri Sep 04 2026 edp17 - 1.2.0-0.7.0
- Release

* Fri Sep 04 2026 edp17 - 1.2.0-0.6.rc6
- Use the Harbour-supported QtFeedback ThemeEffect API for stone haptics
- Play enabled haptics for every successfully placed human or AI stone

* Fri Sep 04 2026 edp17 - 1.2.0-0.5.rc5
- Use Sailfish's standard short tacticon event for placement haptics

* Fri Sep 04 2026 edp17 - 1.2.0-0.4.rc4
- Prevent unavailable haptic feedback from blocking stone placement
- Apply board-size and rule selections immediately on an empty board

* Fri Sep 04 2026 edp17 - 1.2.0-0.3.rc3
- Restore unfinished games and detect full-board draws
- Add board/rule variants, accessibility controls and optional haptics
- Add illustrated rules, statistics, streaks and active-game confirmation
- Rename Unbeatable to Expert while preserving existing settings and records

* Thu Sep 03 2026 edp17 - 1.2.0-0.2.rc2
- Replace heuristic-only move selection with a threaded C++ alpha-beta engine
- Strengthen tactical defence and deeper Hard/Unbeatable opponent search
- Incorporate reviewed Hungarian translations

* Thu Sep 03 2026 edp17 - 1.2.0-0.1.rc1
- Enable Sailjail sandboxing and Hungarian localization
- Replace Undo and Redo pulley actions with page icons
- Move Best Times to Settings and improve AI variety and difficulty progression

* Fri Dec 12 2025 edp17 - 1.0.0-1
- Initial package
