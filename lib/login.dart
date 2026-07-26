import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'teacherdashboard.dart';
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget{
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const Login(),
    );
  }
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login>{
  
  final TextEditingController email=TextEditingController();
  final TextEditingController password=TextEditingController();

  bool _isLoading = false;
  
     Future<void> loginUser() async {
    var url = Uri.parse('http://192.168.0.196:8000/accounts/login/');

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        url,
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'email': email.text,
          'password': password.text,
        }),
      );

      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final teacherId = data['admin']['tid'];
        final teacherName=data['admin']['username'];

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => Teacherdashboard(teacherId: teacherId, teacherName: teacherName),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Login failed: ${response.body}')),
          );
        }
      }
    } catch (e) {
      print('Login request failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not connect to server')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Light grey background

      body: Column(
        children: [
          Container(
            color: const Color(0xFF212529),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Click-digitals Courses App',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Login', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),

          Expanded(
            child: Center(
            child:SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 450), // Keeps form centered on web
                child: Card(
                  color:Colors.orange,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  margin: const EdgeInsets.all(20),
                  child: Padding(
                    padding: const EdgeInsets.all(30.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller:email,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller:password,
                          decoration: const InputDecoration(labelText: 'Password'),
                          obscureText: true,
                        ),
                        const SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0A838A),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                             onPressed: () async {
                                  await loginUser();
                             },
                            child: const Text('Login', style: TextStyle(fontSize: 18, color: Colors.white)),
                          ),
                          
                        ),
                        const SizedBox(height: 20),
                          
                          GestureDetector(
                            onTap: () {
                              Navigator.pushNamed(context, '/reg'); // Navigate to login page
                            },
                            child:
                          const Text("Don't have an account? Register here", style: TextStyle(color: Colors.blue, decoration:TextDecoration.underline,)), 
                          )
                        
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ),
        ],
      
      ),
    );
  }
}