import 'package:flutter/material.dart';

/// The root navigator's routes, bottom first: [Navigator] does not list them.
final class RootRoutes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  // go_router also reports the tab navigators' routes here.
  bool _isRoot(Route<dynamic> route) => route.navigator == navigator;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isRoot(route)) routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final at = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (at < 0) {
      if (newRoute != null && _isRoot(newRoute)) routes.add(newRoute);
    } else if (newRoute == null) {
      routes.removeAt(at);
    } else {
      routes[at] = newRoute;
    }
  }

  /// Whether replacing the pages would drop a dialog, a sheet or a page that
  /// refuses Back (an unsaved form). Every route counts, not only the top one:
  /// a page opened above a form leaves the form below it.
  bool get wouldLoseSomething => routes.any(
    (r) => r is PopupRoute || r.popDisposition == RoutePopDisposition.doNotPop,
  );
}

/// Gives the screens the root navigator's routes, to ask before they rebuild
/// the page stack.
class RootRoutesScope extends InheritedWidget {
  const RootRoutesScope({
    super.key,
    required this.routes,
    required super.child,
  });
  final RootRoutes routes;

  /// Null outside the app, where nothing is kept below a screen.
  static RootRoutes? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RootRoutesScope>()?.routes;

  @override
  bool updateShouldNotify(RootRoutesScope old) => routes != old.routes;
}
