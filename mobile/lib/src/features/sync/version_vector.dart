enum VectorRelation { equal, before, after, concurrent }

VectorRelation compareVectors(Map<String, int> left, Map<String, int> right) {
  var leftGreater = false;
  var rightGreater = false;
  for (final device in {...left.keys, ...right.keys}) {
    final a = left[device] ?? 0;
    final b = right[device] ?? 0;
    if (a > b) leftGreater = true;
    if (b > a) rightGreater = true;
  }
  if (leftGreater && rightGreater) return VectorRelation.concurrent;
  if (leftGreater) return VectorRelation.after;
  if (rightGreater) return VectorRelation.before;
  return VectorRelation.equal;
}

Map<String, int> mergeVectors(Map<String, int> left, Map<String, int> right) => {
  for (final device in {...left.keys, ...right.keys})
    device: (left[device] ?? 0) > (right[device] ?? 0)
        ? left[device] ?? 0
        : right[device] ?? 0,
};
