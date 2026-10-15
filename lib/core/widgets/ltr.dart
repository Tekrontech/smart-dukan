import 'package:flutter/material.dart';

/// Forces left-to-right for numbers, IMEIs, phone numbers and SKUs, which
/// must stay LTR even in Urdu mode (spec Section 4).
class Ltr extends StatelessWidget {
  const Ltr(this.child, {super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.ltr, child: child);
}
