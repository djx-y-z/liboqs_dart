import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:liboqs/liboqs.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LibOQS.init();
  runApp(const LiboqsExampleApp());
}

class LiboqsExampleApp extends StatelessWidget {
  const LiboqsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'liboqs Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _output = '';
  bool _isRunning = false;

  void _appendOutput(String text) {
    setState(() {
      _output += '$text\n';
    });
  }

  void _clearOutput() {
    setState(() {
      _output = '';
    });
  }

  Future<void> _runDemo(String name, Future<void> Function() demo) async {
    if (_isRunning) return;

    setState(() {
      _isRunning = true;
      _output = '=== $name ===\n\n';
    });

    try {
      await demo();
    } catch (e) {
      _appendOutput('\nError: $e');
    } finally {
      setState(() {
        _isRunning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('liboqs Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearOutput,
            tooltip: 'Clear output',
          ),
        ],
      ),
      body: Column(
        children: [
          // Library info card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'liboqs v${LibOQS.getVersion()}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${LibOQS.getSupportedKEMAlgorithms().length} KEM algorithms, '
                    '${LibOQS.getSupportedSignatureAlgorithms().length} Signature algorithms',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),

          // Demo buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DemoButton(
                  label: 'KEM Demo',
                  icon: Icons.vpn_key,
                  isRunning: _isRunning,
                  onPressed: () =>
                      _runDemo('Key Encapsulation (ML-KEM-768)', _runKemDemo),
                ),
                _DemoButton(
                  label: 'Signature Demo',
                  icon: Icons.verified,
                  isRunning: _isRunning,
                  onPressed: () => _runDemo(
                    'Digital Signatures (ML-DSA-65)',
                    _runSignatureDemo,
                  ),
                ),
                _DemoButton(
                  label: 'Random Demo',
                  icon: Icons.casino,
                  isRunning: _isRunning,
                  onPressed: () =>
                      _runDemo('Random Generation', _runRandomDemo),
                ),
                _DemoButton(
                  label: 'All Algorithms',
                  icon: Icons.list,
                  isRunning: _isRunning,
                  onPressed: () =>
                      _runDemo('Supported Algorithms', _runAlgorithmsDemo),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Output area
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SizedBox(
                  width: double.infinity,
                  child: SelectableText(
                    _output.isEmpty ? 'Tap a button to run a demo...' : _output,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: _output.isEmpty ? Colors.grey : Colors.green[300],
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

  Future<void> _runKemDemo() async {
    final kem = KEM.create('ML-KEM-768');

    try {
      _appendOutput('Algorithm: ML-KEM-768');
      _appendOutput('Public key: ${kem.publicKeyLength} bytes');
      _appendOutput('Secret key: ${kem.secretKeyLength} bytes');
      _appendOutput('Ciphertext: ${kem.ciphertextLength} bytes');
      _appendOutput('Shared secret: ${kem.sharedSecretLength} bytes');
      _appendOutput('');

      // Generate key pair
      final keyPair = kem.generateKeyPair();
      _appendOutput('[+] Generated key pair');

      // Encapsulate
      final encResult = kem.encapsulate(keyPair.publicKey);
      _appendOutput('[+] Encapsulated shared secret');

      // Decapsulate
      final sharedSecret = kem.decapsulate(
        encResult.ciphertext,
        keyPair.secretKey,
      );
      _appendOutput('[+] Decapsulated shared secret');

      // Verify
      final match = _compareBytes(encResult.sharedSecret, sharedSecret);
      _appendOutput('[+] Secrets match: $match');
      _appendOutput('');
      _appendOutput('Shared secret (first 32 bytes):');
      _appendOutput(_bytesToHex(sharedSecret.take(32).toList()));

      // Deterministic generation
      if (kem.supportsDeterministicGeneration) {
        _appendOutput('');
        _appendOutput('--- Deterministic Key Generation ---');
        final seed = OQSRandom.generateSeed(kem.seedLength!);
        final kp1 = kem.generateKeyPairDerand(seed);
        final kp2 = kem.generateKeyPairDerand(seed);
        final identical = _compareBytes(kp1.publicKey, kp2.publicKey);
        _appendOutput('[+] Same seed produces identical keys: $identical');
      }
    } finally {
      kem.dispose();
    }
  }

  Future<void> _runSignatureDemo() async {
    final sig = Signature.create('ML-DSA-65');

    try {
      _appendOutput('Algorithm: ML-DSA-65');
      _appendOutput('Public key: ${sig.publicKeyLength} bytes');
      _appendOutput('Secret key: ${sig.secretKeyLength} bytes');
      _appendOutput('Max signature: ${sig.maxSignatureLength} bytes');
      _appendOutput('');

      // Generate key pair
      final keyPair = sig.generateKeyPair();
      _appendOutput('[+] Generated key pair');

      // Sign message
      final message = Uint8List.fromList(
        utf8.encode('Hello, Post-Quantum World!'),
      );
      final signature = sig.sign(message, keyPair.secretKey);
      _appendOutput('[+] Signed message (${signature.length} bytes)');

      // Verify
      final isValid = sig.verify(message, signature, keyPair.publicKey);
      _appendOutput('[+] Signature valid: $isValid');

      // Test with wrong message
      final wrongMessage = Uint8List.fromList(utf8.encode('Wrong message'));
      final isInvalid = sig.verify(wrongMessage, signature, keyPair.publicKey);
      _appendOutput('[+] Wrong message rejected: ${!isInvalid}');
    } finally {
      sig.dispose();
    }
  }

  Future<void> _runRandomDemo() async {
    _appendOutput('Generating random data...');
    _appendOutput('');

    // Random bytes
    final bytes = OQSRandom.generateBytes(32);
    _appendOutput('32 random bytes:');
    _appendOutput(_bytesToHex(bytes.toList()));
    _appendOutput('');

    // Random integers
    final ints = List.generate(10, (_) => OQSRandom.generateInt(1, 100));
    _appendOutput('10 random integers (1-99): $ints');

    // Random booleans
    final bools = List.generate(10, (_) => OQSRandom.generateBool());
    _appendOutput('10 random booleans: $bools');

    // Random doubles
    final doubles = List.generate(5, (_) => OQSRandom.generateDouble());
    _appendOutput(
      '5 random doubles: ${doubles.map((d) => d.toStringAsFixed(4)).toList()}',
    );

    // Shuffle demo
    final list = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    _appendOutput('');
    _appendOutput('Original list: $list');
    OQSRandom.shuffleList(list);
    _appendOutput('Shuffled list: $list');

    // Available algorithms
    _appendOutput('');
    _appendOutput(
      'Available RNG algorithms: ${OQSRandom.getAvailableAlgorithms()}',
    );
  }

  Future<void> _runAlgorithmsDemo() async {
    final kems = LibOQS.getSupportedKEMAlgorithms();
    final sigs = LibOQS.getSupportedSignatureAlgorithms();

    _appendOutput('Key Encapsulation Mechanisms (${kems.length}):');
    for (final alg in kems) {
      _appendOutput('  - $alg');
    }

    _appendOutput('');
    _appendOutput('Digital Signatures (${sigs.length}):');
    for (final alg in sigs) {
      _appendOutput('  - $alg');
    }
  }

  bool _compareBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }
}

class _DemoButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isRunning;
  final VoidCallback onPressed;

  const _DemoButton({
    required this.label,
    required this.icon,
    required this.isRunning,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isRunning ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}
