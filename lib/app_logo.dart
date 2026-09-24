import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double radius;
  const AppLogo({super.key, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
    //  backgroundColor: Colors.white,
      backgroundImage: const AssetImage('assets/icon/icon.png'),
    );
  }
}