import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

void main() {
  Geolocator.requestPermission();
  runApp(const RunTrackerApp());
}

class RunTrackerApp extends StatelessWidget {
  const RunTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Run Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const RunTrackerHome(),
    );
  }
}

class RunTrackerHome extends StatefulWidget {
  const RunTrackerHome({super.key});

  @override
  State<RunTrackerHome> createState() => _RunTrackerHomeState();
}

class _RunTrackerHomeState extends State<RunTrackerHome> {
  bool isRunning = false;
  bool isPaused = false;
  bool autoStopEnabled = false;
  List<LatLng> routePoints = [];
  DateTime? startTime;
  Timer? timer;
  double distance = 0;
  Duration elapsed = Duration.zero;
  LatLng? startPosition;
  StreamSubscription<Position>? positionStream;
  bool useMetric = true;
  static const double kmToMilesConversion = 0.621371;

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
    _loadPreferences();
    _initializeUnitPreference();
  }

  Future<void> _initializeUnitPreference() async {
    // Get the current locale
    final locale = WidgetsBinding.instance.window.locale.countryCode;
    // Default to metric unless in US
    final defaultToMetric = locale != 'US';

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      useMetric = prefs.getBool('useMetric') ?? defaultToMetric;
    });
  }

  Future<void> _saveUnitPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('useMetric', useMetric);
  }

  String formatDistance(double distanceInMeters) {
    final distanceInKm = distanceInMeters / 1000;
    if (useMetric) {
      return '${distanceInKm.toStringAsFixed(2)} km';
    } else {
      final distanceInMiles = distanceInKm * kmToMilesConversion;
      return '${distanceInMiles.toStringAsFixed(2)} mi';
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      autoStopEnabled = prefs.getBool('autoStopEnabled') ?? false;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoStopEnabled', autoStopEnabled);
  }

  Future<void> _requestLocationPermission() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      // Handle denied permission
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission is required')),
      );
    }
  }

  void startRun() async {
    // Start timer immediately
    setState(() {
      isRunning = true;
      startTime = DateTime.now();
      distance = 0;
      routePoints = [];
    });

    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isPaused) {
        setState(() {
          elapsed = DateTime.now().difference(startTime!);
        });
      }
    });

    // Get GPS position in parallel
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );

      setState(() {
        startPosition = LatLng(position.latitude, position.longitude);
        routePoints = [startPosition!];
      });

      // Start position stream after getting initial position
      positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) {
        final newPoint = LatLng(position.latitude, position.longitude);

        if (routePoints.isNotEmpty) {
          final lastPoint = routePoints.last;
          distance += Geolocator.distanceBetween(
            lastPoint.latitude,
            lastPoint.longitude,
            newPoint.latitude,
            newPoint.longitude,
          );
        }

        setState(() {
          routePoints.add(newPoint);
        });

        if (autoStopEnabled &&
            elapsed.inMinutes >= 1 &&
            startPosition != null &&
            _isNearStartPosition(position)) {
          stopRun();
        }
      });
    } catch (e) {
      // Handle GPS acquisition error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Unable to acquire GPS position. Please check your location settings.')),
      );
    }
  }

  bool _isNearStartPosition(Position currentPosition) {
    if (startPosition == null) return false;

    final distanceToStart = Geolocator.distanceBetween(
      startPosition!.latitude,
      startPosition!.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );

    return distanceToStart < 20; // Within 20 meters of start
  }

  void pauseRun() {
    setState(() {
      isPaused = !isPaused;
    });
  }

  void stopRun() {
    timer?.cancel();
    positionStream?.cancel();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RunSummaryScreen(
          distance: distance,
          duration: elapsed,
          routePoints: routePoints,
          useMetric: useMetric,
        ),
      ),
    ).then((_) {
      setState(() {
        isRunning = false;
        isPaused = false;
        distance = 0;
        elapsed = Duration.zero;
        routePoints = [];
        startPosition = null;
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Run Tracker'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SwitchListTile(
            title: const Text('Auto-stop when returning to start'),
            value: autoStopEnabled,
            onChanged: (bool value) {
              setState(() {
                autoStopEnabled = value;
                _savePreferences();
              });
            },
          ),
          SwitchListTile(
            title: Text('Use ${useMetric ? "Kilometers" : "Miles"}'),
            value: useMetric,
            onChanged: (bool value) {
              setState(() {
                useMetric = value;
                _saveUnitPreference();
              });
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Time: ${elapsed.inMinutes}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            'Distance: ${formatDistance(distance)}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          if (!isRunning)
            ElevatedButton(
              onPressed: startRun,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: const Text('Start Run'),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: pauseRun,
                  child: Text(isPaused ? 'Resume' : 'Pause'),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  onPressed: stopRun,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Stop'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class RunSummaryScreen extends StatelessWidget {
  final double distance;
  final Duration duration;
  final List<LatLng> routePoints;
  final bool useMetric;
  static const double kmToMilesConversion = 0.621371;

  const RunSummaryScreen({
    super.key,
    required this.distance,
    required this.duration,
    required this.routePoints,
    required this.useMetric,
  });

  String formatDistance(double distanceInMeters) {
    final distanceInKm = distanceInMeters / 1000;
    if (useMetric) {
      return '${distanceInKm.toStringAsFixed(2)} km';
    } else {
      final distanceInMiles = distanceInKm * kmToMilesConversion;
      return '${distanceInMiles.toStringAsFixed(2)} mi';
    }
  }

  String formatPace(double distanceInMeters) {
    if (distanceInMeters == 0) return '--:-- /km';

    final distanceInKm = distanceInMeters / 1000;
    final seconds = duration.inSeconds;

    if (useMetric) {
      final pacePerKm = seconds / distanceInKm;
      return '${(pacePerKm / 60).floor()}:${((pacePerKm % 60).round()).toString().padLeft(2, '0')} /km';
    } else {
      final distanceInMiles = distanceInKm * kmToMilesConversion;
      final pacePerMile = seconds / distanceInMiles;
      return '${(pacePerMile / 60).floor()}:${((pacePerMile % 60).round()).toString().padLeft(2, '0')} /mi';
    }
  }

  // In RunSummaryScreen class, update the build method:
  @override
  Widget build(BuildContext context) {
    final pace = duration.inSeconds / (distance / 1000); // seconds per km

    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const RunTrackerHome()),
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Run Summary'),
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            Expanded(
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: routePoints.first,
                  zoom: 15,
                ),
                polylines: {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: routePoints,
                    color: Colors.blue,
                    width: 5,
                  ),
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('start'),
                    position: routePoints.first,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                  ),
                  Marker(
                    markerId: const MarkerId('end'),
                    position: routePoints.last,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
                  ),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    'Distance: ${(distance / 1000).toStringAsFixed(2)} km',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Time: ${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    'Pace: ${(pace / 60).floor()}:${((pace % 60).round()).toString().padLeft(2, '0')} /km',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const RunTrackerHome()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                    child: const Text('Start New Run'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
