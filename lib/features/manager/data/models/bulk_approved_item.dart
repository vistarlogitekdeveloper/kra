import '../../../../core/api/json_parse.dart';

/// One row in the `approved` section of a bulk-approve response.
class BulkApprovedItem {
  final String reviewId;
  final String employeeName;
  final String? employeeCode;
  final double? managerTotal;

  const BulkApprovedItem({
    required this.reviewId,
    required this.employeeName,
    this.employeeCode,
    this.managerTotal,
  });

  factory BulkApprovedItem.fromJson(Map<String, dynamic> json) =>
      BulkApprovedItem(
        reviewId: JsonParse.parseString(json['reviewId']) ?? '',
        employeeName:
            JsonParse.parseString(json['employeeName']) ?? '',
        employeeCode:
            JsonParse.parseString(json['employeeCode']),
        managerTotal: JsonParse.parseDouble(json['managerTotal']),
      );

  Map<String, dynamic> toJson() => {
        'reviewId': reviewId,
        'employeeName': employeeName,
        'employeeCode': employeeCode,
        'managerTotal': managerTotal,
      };
}
