// A simple course table app
// Copyright (C) 2023 Zhihao Zhou
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:flutter_course_table/constants.dart';
import 'package:flutter_course_table/internal/types/course_table.dart';
import 'package:flutter_course_table/internal/utils/course_table_json_handlers.dart';
import 'package:flutter_course_table/internal/utils/database_utils.dart';
import 'package:flutter_course_table/pages/home_page/course_table_widget_builder.dart';
import 'package:flutter_course_table/pages/import_page/import_page.dart';
import 'package:flutter_course_table/pages/settings_page/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqlite3/common.dart' as sqlite3;

class CourseTableHomePage extends StatefulWidget {
  final CourseTable? initCourseTable;
  final List<String> names;
  final bool useLightMode;
  final void Function(bool useLightMode) handleBrightnessChange;
  final SharedPreferences prefs;
  final Database database;

  const CourseTableHomePage({
    super.key,
    required this.initCourseTable,
    required this.names,
    required this.useLightMode,
    required this.handleBrightnessChange,
    required this.prefs,
    required this.database,
  });

  @override
  State<CourseTableHomePage> createState() => _CourseTableHomePageState();
}

class _CourseTableHomePageState extends State<CourseTableHomePage> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  String currCourseTableName = "";
  int currPage = 0;
  CourseTable? courseTable;
  List<String> names = [];
  List<DropdownMenuEntry<String>> tableEntries = [];
  List<DropdownMenuEntry<int>> weekEntries = [];
  late final AnimationController controller;
  late final CurvedAnimation railAnimation;
  late final ReverseAnimation barAnimation;
  bool controllerInitialized = false;
  bool showLargeSizeLayout = false;

  int screenIndex = ScreenSelected.courseTable.value;

  @override
  void initState() {
    super.initState();
    currCourseTableName = widget.prefs.getString("currCourseTableName") ?? "";
    courseTable = widget.initCourseTable;
    names = widget.names;
    currPage = getCurrCourseTableInitialPage();
    tableEntries = getStoredCourseTableEntries();
    weekEntries = getStoredCourseTableWeekEntries();
    controller = AnimationController(
      duration: Duration(milliseconds: transitionLength.toInt() * 2),
      value: 0,
      vsync: this,
    );
    railAnimation = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.5, 1.0),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final double width = MediaQuery.of(context).size.width;
    final AnimationStatus status = controller.status;
    if (width > largeWidthBreakpoint) {
      showLargeSizeLayout = true;
      if (status != AnimationStatus.forward &&
          status != AnimationStatus.completed) {
        controller.forward();
      }
    } else {
      showLargeSizeLayout = false;
      if (status != AnimationStatus.reverse &&
          status != AnimationStatus.dismissed) {
        controller.reverse();
      }
    }
    if (!controllerInitialized) {
      controllerInitialized = true;
      controller.value = width > largeWidthBreakpoint ? 1 : 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return NavigationTransition(
          scaffoldKey: scaffoldKey,
          animationController: controller,
          railAnimation: railAnimation,
          appBar: createAppBar(),
          body: createScreenFor(ScreenSelected.values[screenIndex]),
          navigationRail: NavigationRail(
            extended: true,
            destinations: navRailDestinations,
            selectedIndex: screenIndex,
            onDestinationSelected: (index) {
              setState(() {
                screenIndex = index;
                handleScreenChanged(screenIndex);
              });
            },
            trailing: Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _expandedTrailingActions()
              ),
            ),
          ),
          navigationBar: NavigationBars(
            onSelectItem: (index) {
              setState(() {
                screenIndex = index;
                handleScreenChanged(screenIndex);
              });
            },
            selectedIndex: screenIndex,
          ),
        );
      },
    );
  }

  Future<void> handleCurrCourseTableChange(String courseTableName) async {
    names = await getCourseTableNames(widget.database);
    final jsonString = await getCourseTableJsonByName(widget.database, courseTableName);
    setState(() {
      currCourseTableName = courseTableName;
      courseTable = jsonToCourseTable(jsonString);
      tableEntries = getStoredCourseTableEntries();
      weekEntries = getStoredCourseTableWeekEntries();
      currPage = getCurrCourseTableInitialPage();
    });
    widget.prefs.setString("currCourseTableName", courseTableName);
  }

  Future<void> handleCourseTableDeleted(String courseTableName) async {
    int cnt = await widget.database.delete('course_tables_table',
        where: 'name = ?', whereArgs: [courseTableName]);
    if (cnt < 1) {
      throw sqlite3.SqliteException(sqlite3.SqlError.SQLITE_NOTFOUND,
          'Nothing found by giving name');
    }

    names = await getCourseTableNames(widget.database);
    setState(() {
      tableEntries = getStoredCourseTableEntries();
    });

    if (currCourseTableName == courseTableName) {
      if (names.isEmpty) {
        setState(() {
          currCourseTableName = "";
          courseTable = null;
          currPage = 0;
        });
        return;
      }
      setState(() {
        handleCurrCourseTableChange(names[0]);
        currPage = 0;
      });
    }
  }

  void handleCurrPageChanged(int page) {
    setState(() {
      currPage = page;
    });
  }

  void handleCourseTableDisposed() {
    currPage = getCurrCourseTableInitialPage();
  }

  void handleScreenChanged(int screenSelected) {
    setState(() {
      screenIndex = screenSelected;
    });
  }

  Widget createScreenFor(ScreenSelected screenSelected) {
    switch (screenSelected) {
      case ScreenSelected.courseTable:
        return courseTable == null || currCourseTableName.isEmpty
            ? Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: Text("未选择或未导入课表，请先选择或导入课表"),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      handleScreenChanged(ScreenSelected.import.value);
                    },
                    child: const Text("导入"),
                  ),
                ],
              )
            )
            : CourseTableWidget(
              initPage: getCurrCourseTableInitialPage(),
              currPage: currPage,
              courseTable: courseTable!,
              handleCurrPageChanged: handleCurrPageChanged,
              handleCourseTableDisposed: handleCourseTableDisposed,
            );
      case ScreenSelected.import:
        return ImportTablePage(
          handleCurrCourseTableChange: handleCurrCourseTableChange,
          prefs: widget.prefs,
          database: widget.database,
        );
      case ScreenSelected.settings:
        return SettingsPage(
          currCourseTableName: currCourseTableName,
          handleBrightnessChange: widget.handleBrightnessChange,
          handleChangeCurrCourseTable: handleCurrCourseTableChange,
          handleDeleteCurrCourseTable: handleCourseTableDeleted,
          prefs: widget.prefs,
          database: widget.database,
        );
      default:
        return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text("未选择或未导入课表，请先选择或导入课表"),
                ),
                ElevatedButton(
                  onPressed: () {
                    handleScreenChanged(ScreenSelected.import.value);
                  },
                  child: const Text("导入"),
                ),
              ],
            )
        );
    }
  }

  PreferredSizeWidget createAppBar() {
    Widget title;
    switch (screenIndex) {
      case 0:
        title = names.isNotEmpty ? _appBarTitle()
            : const Text("Flutter Course Table");
        break;
      case 1:
        title = const Text("导入课表");
        break;
      case 2:
        title = const Text("设置");
        break;
      default:
        title = const Text("Flutter Course Table");
    }

    return AppBar(
      title: title,
      notificationPredicate: (ScrollNotification notification) {
        return notification.depth == 1;
      },
      scrolledUnderElevation: 4.0,
      actions: (!showLargeSizeLayout)
          ? [_BrightnessButton(
                handleBrightnessChange: widget.handleBrightnessChange,
              ),
            ]
          : [Container()],
    );
  }

  Widget _appBarTitle() => Container(
      alignment: Alignment.bottomLeft,
      child: FittedBox(
        child: Row(
          children: [
            DropdownMenu(
              menuHeight: 400,
              leadingIcon: const Icon(Icons.table_chart),
              initialSelection: currCourseTableName,
              inputDecorationTheme: const InputDecorationTheme(
                  isCollapsed: true
              ),
              dropdownMenuEntries: tableEntries,
              onSelected: (value) async {
                if (value == null || value.isEmpty) return;
                await handleCurrCourseTableChange(value);
              },
            ),
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: DropdownMenu(
                menuHeight: 400,
                leadingIcon: const Icon(Icons.calendar_today),
                initialSelection: currPage,
                inputDecorationTheme: const InputDecorationTheme(
                    isCollapsed: true
                ),
                dropdownMenuEntries: weekEntries,
                onSelected: (value) {
                  if (value == null) return;
                  handleCurrPageChanged(value);
                },
              ),
            )
          ],
        ),
      ),
  );

  int getCurrCourseTableInitialPage() {
    if (courseTable == null) return 0;
    DateTime firstWeekDateTime = DateTime.parse(courseTable!.firstWeekDate);
    if (DateTime.now().isBefore(firstWeekDateTime)) return 0;
    int currWeek = DateTime.now().difference(firstWeekDateTime).inDays ~/ 7;
    if (currWeek > (courseTable!.week!)) {
      return courseTable!.week! - 1;
    }
    return currWeek;
  }

  Widget _expandedTrailingActions() => Container(
    alignment: Alignment.bottomCenter,
    constraints: const BoxConstraints.tightFor(width: 250),
    padding: const EdgeInsets.symmetric(horizontal: 30),
    child: ListView(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Divider(),
            Row(
              children: [
                widget.useLightMode
                    ? const Icon(Icons.light_mode_outlined)
                    : const Icon(Icons.dark_mode_outlined),
                const Text('更改显示模式'),
                Expanded(child: Container()),
                Switch(
                    value: widget.useLightMode,
                    onChanged: (value) {
                      widget.handleBrightnessChange(value);
                    }),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  List<DropdownMenuEntry<String>> getStoredCourseTableEntries() {
    List<DropdownMenuEntry<String>> items = [];
    for (var element in names) {
      items.add(DropdownMenuEntry(value: element, label: element));
    }
    return items;
  }

  List<DropdownMenuEntry<int>> getStoredCourseTableWeekEntries() {
    List<DropdownMenuEntry<int>> items = [];
    if (courseTable == null) return items;
    for (int i = 0; i < (courseTable!.week ?? 0); i++) {
      items.add(DropdownMenuEntry(value: i, label: "第${i+1}周"));
    }
    return items;
  }
}

class NavigationBars extends StatefulWidget {
  const NavigationBars({
    super.key,
    this.onSelectItem,
    required this.selectedIndex,
  });

  final void Function(int)? onSelectItem;
  final int selectedIndex;

  @override
  State<NavigationBars> createState() => _NavigationBarsState();
}

class _NavigationBarsState extends State<NavigationBars> {
  late int selectedIndex;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.selectedIndex;
  }

  @override
  void didUpdateWidget(covariant NavigationBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      selectedIndex = widget.selectedIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget navigationBar = Focus(
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
          widget.onSelectItem!(index);
        },
        destinations: appBarDestinations,
      ),
    );

    return navigationBar;
  }
}

class NavigationTransition extends StatefulWidget {
  const NavigationTransition(
      {super.key,
        required this.scaffoldKey,
        required this.animationController,
        required this.railAnimation,
        required this.navigationRail,
        required this.navigationBar,
        required this.appBar,
        required this.body});

  final GlobalKey<ScaffoldState> scaffoldKey;
  final AnimationController animationController;
  final CurvedAnimation railAnimation;
  final Widget navigationRail;
  final Widget navigationBar;
  final PreferredSizeWidget appBar;
  final Widget body;

  @override
  State<NavigationTransition> createState() => _NavigationTransitionState();
}

class _NavigationTransitionState extends State<NavigationTransition> {
  late final AnimationController controller;
  late final CurvedAnimation railAnimation;
  late final ReverseAnimation barAnimation;
  bool controllerInitialized = false;
  bool showDivider = false;

  @override
  void initState() {
    super.initState();

    controller = widget.animationController;
    railAnimation = widget.railAnimation;

    barAnimation = ReverseAnimation(
      CurvedAnimation(
        parent: controller,
        curve: const Interval(0.0, 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: widget.scaffoldKey,
      appBar: widget.appBar,
      body: Row(
        children: <Widget>[
          RailTransition(
            animation: railAnimation,
            backgroundColor: colorScheme.surface,
            child: widget.navigationRail,
          ),
          widget.body,
        ],
      ),
      bottomNavigationBar: BarTransition(
        animation: barAnimation,
        backgroundColor: colorScheme.surface,
        child: widget.navigationBar,
      ),
    );
  }
}

final List<NavigationRailDestination> navRailDestinations = appBarDestinations
    .map(
      (destination) => NavigationRailDestination(
    icon: Tooltip(
      message: destination.label,
      child: destination.icon,
    ),
    selectedIcon: Tooltip(
      message: destination.label,
      child: destination.selectedIcon,
    ),
    label: Text(destination.label),
  ),
)
    .toList();

class SizeAnimation extends CurvedAnimation {
  SizeAnimation(Animation<double> parent)
      : super(
    parent: parent,
    curve: const Interval(
      0.2,
      0.8,
      curve: Curves.easeInOutCubicEmphasized,
    ),
    reverseCurve: Interval(
      0,
      0.2,
      curve: Curves.easeInOutCubicEmphasized.flipped,
    ),
  );
}

class OffsetAnimation extends CurvedAnimation {
  OffsetAnimation(Animation<double> parent)
      : super(
    parent: parent,
    curve: const Interval(
      0.4,
      1.0,
      curve: Curves.easeInOutCubicEmphasized,
    ),
    reverseCurve: Interval(
      0,
      0.2,
      curve: Curves.easeInOutCubicEmphasized.flipped,
    ),
  );
}

class RailTransition extends StatefulWidget {
  const RailTransition(
      {super.key,
        required this.animation,
        required this.backgroundColor,
        required this.child});

  final Animation<double> animation;
  final Widget child;
  final Color backgroundColor;

  @override
  State<RailTransition> createState() => _RailTransition();
}

class _RailTransition extends State<RailTransition> {
  late Animation<Offset> offsetAnimation;
  late Animation<double> widthAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // The animations are only rebuilt by this method when the text
    // direction changes because this widget only depends on Directionality.
    final bool ltr = Directionality.of(context) == TextDirection.ltr;

    widthAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(SizeAnimation(widget.animation));

    offsetAnimation = Tween<Offset>(
      begin: ltr ? const Offset(-1, 0) : const Offset(1, 0),
      end: Offset.zero,
    ).animate(OffsetAnimation(widget.animation));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.backgroundColor),
        child: Align(
          alignment: Alignment.topLeft,
          widthFactor: widthAnimation.value,
          child: FractionalTranslation(
            translation: offsetAnimation.value,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class BarTransition extends StatefulWidget {
  const BarTransition(
      {super.key,
        required this.animation,
        required this.backgroundColor,
        required this.child});

  final Animation<double> animation;
  final Color backgroundColor;
  final Widget child;

  @override
  State<BarTransition> createState() => _BarTransition();
}

class _BarTransition extends State<BarTransition> {
  late final Animation<Offset> offsetAnimation;
  late final Animation<double> heightAnimation;

  @override
  void initState() {
    super.initState();

    offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(OffsetAnimation(widget.animation));

    heightAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(SizeAnimation(widget.animation));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.backgroundColor),
        child: Align(
          alignment: Alignment.topLeft,
          heightFactor: heightAnimation.value,
          child: FractionalTranslation(
            translation: offsetAnimation.value,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _BrightnessButton extends StatelessWidget {
  final Function handleBrightnessChange;
  final bool showTooltipBelow = true;

  const _BrightnessButton({
    required this.handleBrightnessChange,
  });

  @override
  Widget build(BuildContext context) {
    final isBright = Theme.of(context).brightness == Brightness.light;
    return Tooltip(
      preferBelow: showTooltipBelow,
      message: '更改显示模式',
      child: IconButton(
        icon: isBright
            ? const Icon(Icons.light_mode_outlined)
            : const Icon(Icons.dark_mode_outlined),
        onPressed: () => handleBrightnessChange(!isBright),
      ),
    );
  }
}
