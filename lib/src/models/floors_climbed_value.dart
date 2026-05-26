class FloorsClimbedValue {
  final double floor;

  const FloorsClimbedValue({required this.floor});

  factory FloorsClimbedValue.fromJson(Map<String, dynamic> json) => FloorsClimbedValue(
        floor: (json['floor'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'floor': floor};
}
