import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class CourseTable {
  String? firstWeekDate;
  final int? row;
  final int? col;
  final int? week;
  final List<List<CourseInfo>>? data;

  CourseTable({
    this.firstWeekDate,
    this.row,
    this.col,
    this.week,
    this.data,
  });

  static Map<String, dynamic> toJson(CourseTable v) {
    return {'firstWeekDate': v.firstWeekDate, 'row': v.row, 'col': v.col, 'week':v.week, 'data':v.data};
  }
}

class CourseInfo {
  final bool isEmpty;
  final String courseId;
  final String courseName;
  final String locationName;
  final int sectionBegin;
  final int sectionLength;
  final int weekNum;
  final int dateNum;

  const CourseInfo({
    this.isEmpty = false,
    required this.courseId,
    required this.courseName,
    required this.locationName,
    required this.sectionBegin,
    required this.sectionLength,
    required this.weekNum,
    required this.dateNum,
  });

  factory CourseInfo.fromJson(Map<String, dynamic> json) => CourseInfo(
      isEmpty: false,
      courseId: json['courseId'].toString(),
      courseName: json['courseName'].toString(),
      locationName: json['locationName'].toString(),
      sectionBegin: json['sectionBegin'] as int,
      sectionLength: json['sectionLength'] as int,
      weekNum: json['weekNum'] as int,
      dateNum: json['dateNum'] as int,
    );

  static Map<String, dynamic> toJson(CourseInfo v) => {
    'isEmpty': v.isEmpty,
    'courseId': v.courseId,
    'courseName': v.courseName,
    'locationName': v.locationName,
    'sectionBegin': v.sectionBegin,
    'sectionLength': v.sectionLength,
    'weekNum': v.weekNum,
    'dateNum': v.dateNum,
  };
}

class SemesterInfo {
  final String value;
  final String index;
  final String semesterId1;
  final String semesterId2;

  const SemesterInfo({
    required this.value,
    required this.index,
    required this.semesterId1,
    required this.semesterId2,
  });
  
  factory SemesterInfo.fromJson(Map<String, dynamic> json) {
    return SemesterInfo(
      value: json['Value'].toString(),
      index: json['Index'].toString(),
      semesterId1: json['SemesterId1'].toString(),
      semesterId2: json['SemesterId2'].toString(),
    );
  }
}

Future<bool> authorizer(String? username, String? password) async {
  http.Response response = await http.get(
    Uri.parse('http://localhost:56789/login'),
    headers: {
      HttpHeaders.authorizationHeader: 'Basic ${utf8.fuse(base64).encode('$username:$password')}'
    },
  );
  if (response.statusCode != 200) {
    return false;
  }
  return true;
}

Future<List<SemesterInfo>?> fetchSemesterList(String? username, String? password) async {
  http.Response response = await http.get(
    Uri.parse('http://localhost:56789/semester-list'),
    headers: {
      HttpHeaders.authorizationHeader: 'Basic ${utf8.fuse(base64).encode('$username:$password')}'
    },
  );

  if (response.statusCode != 200) {
    return null;
  }

  return parseSemesterInfo(response.bodyBytes);
}

Future<List<SemesterInfo>> parseSemesterInfo(Uint8List responseBody) async {
  var responseString = const Utf8Decoder().convert(responseBody);

  final json = jsonDecode(responseString).cast<Map<String, dynamic>>();
  return json.map<SemesterInfo>((json) => SemesterInfo.fromJson(json)).toList();
}

Future<CourseTable?> fetchCourseTable(String? username, String? password, String? semesterId, String? firstWeekDate) async {
  if (username == null || password == null || semesterId == null || firstWeekDate == null) return null;
  http.Response response = await http.get(
    Uri.parse('http://localhost:56789/course-table'),
    headers: {
      HttpHeaders.authorizationHeader: 'Basic ${utf8.fuse(base64).encode('$username:$password')}',
      'semesterId': semesterId,
    },
  );

  if (response.statusCode != 200) return null;

  return await parseCourseInfo(response.bodyBytes, firstWeekDate);
}

Future<CourseTable> parseCourseInfo(Uint8List responseBody, String firstWeekDate) async {
  var responseString = const Utf8Decoder().convert(responseBody);

  final json = jsonDecode(responseString);
  final List<dynamic> dataJson = json['data'];
  List<List<CourseInfo>> data = [[]];
  for (int i = 0; i < dataJson.length; i++) {
    for (int j = 0; j < dataJson[i].length; j++) {
      var tmp = CourseInfo.fromJson(dataJson[i][j]);
      data[i].add(tmp);
    }
    if (i != dataJson.length-1) data.add(<CourseInfo>[]);
  }
  CourseTable courseTable = CourseTable(
    firstWeekDate: firstWeekDate,
    row: json['row'],
    col: json['col'],
    week: json['week'],
    data: data,
  );
  return courseTable;
}
