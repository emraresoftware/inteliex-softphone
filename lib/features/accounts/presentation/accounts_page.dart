import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/app_state_scope.dart';
import '../../../core/models/sip_account.dart';
import '../../../services/sip/softphone_controller.dart';

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);
    final theme = Theme.of(context);

    if (controller.accounts.isEmpty) {
      return _OnboardingView(controller: controller);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'SIP hesaplari',
                  style: theme.textTheme.headlineMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showAccountSheet(context, controller),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Hesap ekle'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: controller.accounts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final account = controller.accounts[index];
                final accountHasActiveCall =
                    controller.activeCall?.accountId == account.id;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    account.displayName,
                                    style: theme.textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(account.aor),
                                ],
                              ),
                            ),
                            _RegistrationBadge(
                              status: account.registrationStatus,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_transportLabel(account.transport)} • ${account.websocketUrl}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF51625C),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'REGISTER: ${account.sipUri}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF51625C),
                          ),
                        ),
                        if (_effectiveAuthUser(account) !=
                            account.username) ...[
                          const SizedBox(height: 4),
                          Text(
                            'AUTH: ${_effectiveAuthUser(account)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF51625C),
                            ),
                          ),
                        ],
                        if (_looksLikeSwappedIdentity(account)) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Bu hesapta Gorunen ad ile Kullanici / dahili alanlari ters girilmis olabilir.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFC88719),
                            ),
                          ),
                        ],
                        if (account.registrationStatus ==
                                RegistrationStatus.failed &&
                            controller.registrationReasonFor(account.id) !=
                                null) ...[
                          const SizedBox(height: 10),
                          Text(
                            controller.registrationReasonFor(account.id)!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _showAccountSheet(
                                context,
                                controller,
                                initialAccount: account,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Duzenle'),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: account.isPrimary
                                  ? null
                                  : () => controller.selectAccount(account.id),
                              icon: const Icon(
                                  Icons.check_circle_outline_rounded),
                              label: Text(
                                account.isPrimary ? 'Aktif hesap' : 'Aktif yap',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  controller.reconnectAccount(account.id),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Yeniden kayitlan'),
                            ),
                            OutlinedButton.icon(
                              onPressed: accountHasActiveCall
                                  ? null
                                  : () => _confirmDeleteAccount(
                                        context,
                                        controller,
                                        account,
                                      ),
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: Text(
                                accountHasActiveCall ? 'Aktif cagrida' : 'Sil',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationBadge extends StatelessWidget {
  const _RegistrationBadge({required this.status});

  final RegistrationStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RegistrationStatus.registered => const Color(0xFF1C7C54),
      RegistrationStatus.connecting => const Color(0xFFC88719),
      RegistrationStatus.failed => const Color(0xFFC13D3D),
      RegistrationStatus.disconnected => const Color(0xFF7B8A84),
    };

    final label = switch (status) {
      RegistrationStatus.registered => 'Kayitli',
      RegistrationStatus.connecting => 'Baglaniyor',
      RegistrationStatus.failed => 'Hatali',
      RegistrationStatus.disconnected => 'Ayrik',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

void _showAccountSheet(
  BuildContext context,
  SoftphoneController controller, {
  SipAccount? initialAccount,
  _AccountFormMode? initialMode,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _AccountSheet(
      controller: controller,
      initialAccount: initialAccount,
      initialMode: initialMode,
    ),
  );
}

Future<void> _confirmDeleteAccount(
  BuildContext context,
  SoftphoneController controller,
  SipAccount account,
) async {
  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Hesabi sil'),
        content: Text(
          '${account.displayName} hesabini cihazdan silmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      );
    },
  );

  if (shouldDelete != true) {
    return;
  }

  await controller.deleteAccount(account.id);
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({
    required this.controller,
    this.initialAccount,
    this.initialMode,
  });

  final SoftphoneController controller;
  final SipAccount? initialAccount;
  final _AccountFormMode? initialMode;

  bool get isEditing => initialAccount != null;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _authorizationUserController;
  late final TextEditingController _passwordController;
  late final TextEditingController _domainController;
  late final TextEditingController _signalingAddressController;
  late final TextEditingController _outboundProxyController;
  late final TextEditingController _stunServerController;
  late final TextEditingController _expireSecondsController;
  late final TextEditingController _inteliexServerController;

  late SipTransport _transport;
  late bool _allowBadCertificate;
  late _AccountFormMode _mode;
  bool _isAdvancedExpanded = false;
  var _isSaving = false;

  List<SipTransport> get _availableTransports {
    final transports = <SipTransport>[
      SipTransport.ws,
      SipTransport.wss,
      SipTransport.tcp,
    ];

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      transports.add(SipTransport.udp);
    }

    if (!transports.contains(_transport)) {
      transports.add(_transport);
    }

    return transports;
  }

  @override
  void initState() {
    super.initState();
    final initialAccount = widget.initialAccount;
    _transport = initialAccount?.transport ?? SipTransport.wss;
    _allowBadCertificate = initialAccount?.allowBadCertificate ?? false;
    _displayNameController = TextEditingController(
      text: initialAccount?.displayName ?? '',
    );
    _usernameController = TextEditingController(
      text: initialAccount?.username ?? '',
    );
    _authorizationUserController = TextEditingController(
      text: initialAccount?.authorizationUser ?? '',
    );
    _passwordController = TextEditingController(
      text: initialAccount?.password ?? '',
    );
    _domainController = TextEditingController(
      text: initialAccount?.domain ?? 'pbx.example.com',
    );
    _signalingAddressController = TextEditingController(
      text: initialAccount?.websocketUrl ?? _defaultAddressFor(_transport),
    );
    _outboundProxyController = TextEditingController(
      text: initialAccount?.outboundProxy ?? '',
    );
    _stunServerController = TextEditingController(
      text: initialAccount?.stunServer ?? '',
    );
    _expireSecondsController = TextEditingController(
      text: (initialAccount?.registrationExpireSeconds ??
              SipAccount.defaultRegistrationExpireSeconds)
          .toString(),
    );
    _isAdvancedExpanded = (initialAccount?.outboundProxy.isNotEmpty ?? false) ||
        (initialAccount?.stunServer.isNotEmpty ?? false) ||
        (initialAccount != null &&
            initialAccount.registrationExpireSeconds !=
                SipAccount.defaultRegistrationExpireSeconds);
    _inteliexServerController = TextEditingController(
      text: initialAccount?.domain ?? '',
    );
    _mode = widget.isEditing
        ? _AccountFormMode.manual
        : widget.initialMode ?? _AccountFormMode.inteliex;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _authorizationUserController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    _signalingAddressController.dispose();
    _outboundProxyController.dispose();
    _stunServerController.dispose();
    _expireSecondsController.dispose();
    _inteliexServerController.dispose();
    super.dispose();
  }

  void _changeTransport(SipTransport nextTransport) {
    if (_transport == nextTransport) {
      return;
    }

    final currentAddress = _signalingAddressController.text.trim();
    final previousDefault = _defaultAddressFor(_transport);
    setState(() {
      _transport = nextTransport;
      if (currentAddress.isEmpty || currentAddress == previousDefault) {
        _signalingAddressController.text = _defaultAddressFor(nextTransport);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEditing ? 'SIP hesabini duzenle' : 'Yeni SIP hesabi',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (!widget.isEditing) ...[
              SegmentedButton<_AccountFormMode>(
                segments: const [
                  ButtonSegment<_AccountFormMode>(
                    value: _AccountFormMode.inteliex,
                    label: Text('Inteliex ile giris'),
                    icon: Icon(Icons.verified_user_outlined),
                  ),
                  ButtonSegment<_AccountFormMode>(
                    value: _AccountFormMode.manual,
                    label: Text('Manuel SIP hesabi'),
                    icon: Icon(Icons.settings_ethernet),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _mode = selection.first;
                  });
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_mode == _AccountFormMode.inteliex && !widget.isEditing)
              ..._buildInteliexFormFields(context)
            else
              ..._buildManualFormFields(context),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSaving ? null : () => _handleSave(context),
                child: Text(
                  _isSaving
                      ? 'Kaydediliyor...'
                      : widget.isEditing
                          ? 'Degisiklikleri kaydet'
                          : 'Kaydet',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildInteliexFormFields(BuildContext context) {
    return [
      Text(
        'Inteliex sunucu bilgilerinizle giris yapin. SIP ayarlari otomatik hazirlanir.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _inteliexServerController,
        decoration: const InputDecoration(
          labelText: 'Inteliex sunucu adresi',
          hintText: 'demo1.sesdata.com',
          helperText:
              'Sadece sunucu adi yazin. WSS ve rehber uc noktasi otomatik olusturulur.',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _usernameController,
        decoration: const InputDecoration(
          labelText: 'Kullanici / dahili',
          helperText:
              'Inteliex panelindeki SIP kullanici adiniz (ornek: 650).',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'SIP sifresi'),
      ),
    ];
  }

  List<Widget> _buildManualFormFields(BuildContext context) {
    return [
      TextField(
        controller: _displayNameController,
        decoration: const InputDecoration(
          labelText: 'Gorunen ad',
          helperText:
              'Sadece uygulama icinde gorunur. REGISTER kullanicisi degildir.',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _usernameController,
        decoration: const InputDecoration(
          labelText: 'Kullanici / dahili',
          helperText:
              'Sunucuya sip:kullanici@domain olarak gider. Zoiper username/ext alaniyla ayni olmalidir.',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _authorizationUserController,
        decoration: const InputDecoration(
          labelText: 'Auth user',
          hintText: 'Bos birakilirsa kullanici alani kullanilir',
          helperText:
              'PBX ayri authentication username istiyorsa doldurun. Cogu durumda kullanici ile aynidir.',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _passwordController,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'SIP sifresi'),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<SipTransport>(
        initialValue: _transport,
        decoration: const InputDecoration(labelText: 'Transport'),
        items: _availableTransports
            .map(
              (transport) => DropdownMenuItem<SipTransport>(
                value: transport,
                child: Text(_transportLabel(transport)),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value == null) {
            return;
          }
          _changeTransport(value);
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _domainController,
        decoration: const InputDecoration(labelText: 'Domain'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _signalingAddressController,
        decoration: InputDecoration(
          labelText: _addressLabelFor(_transport),
          hintText: _addressHintFor(_transport),
          helperText: _addressHelperFor(_transport),
        ),
      ),
      if (_transport == SipTransport.wss) ...[
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _allowBadCertificate,
          onChanged: (value) {
            setState(() {
              _allowBadCertificate = value;
            });
          },
          title: const Text('Test ortaminda gecersiz sertifikaya izin ver'),
        ),
      ],
      const SizedBox(height: 8),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          initiallyExpanded: _isAdvancedExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              _isAdvancedExpanded = expanded;
            });
          },
          title: const Text('Gelismis ayarlar'),
          subtitle: const Text(
            'Outbound proxy, STUN sunucusu ve REGISTER yenileme suresi.',
          ),
          children: [
            const SizedBox(height: 4),
            TextField(
              controller: _outboundProxyController,
              decoration: const InputDecoration(
                labelText: 'Outbound proxy',
                hintText: 'sip:proxy.ornek.com:5060',
                helperText:
                    'Bos birakilirsa sinyal adresi/domain kullanilir.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _stunServerController,
              decoration: const InputDecoration(
                labelText: 'STUN sunucusu',
                hintText: 'stun:stun.l.google.com:19302',
                helperText:
                    'NAT arkasinda medya yolu icin opsiyonel STUN sunucusu.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _expireSecondsController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'REGISTER yenileme (saniye)',
                hintText:
                    SipAccount.defaultRegistrationExpireSeconds.toString(),
                helperText:
                    'Onerilen ${SipAccount.minRegistrationExpireSeconds}-${SipAccount.maxRegistrationExpireSeconds} saniye araligi.',
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _handleSave(BuildContext context) async {
    setState(() {
      _isSaving = true;
    });

    final bool saved;
    if (_mode == _AccountFormMode.inteliex && !widget.isEditing) {
      final server = _inteliexServerController.text.trim();
      final username = _usernameController.text.trim();
      saved = await widget.controller.addAccount(
        displayName: username,
        username: username,
        authorizationUser: username,
        password: _passwordController.text,
        domain: server,
        signalingAddress: server.isEmpty ? '' : 'wss://$server:8089/ws',
        transport: SipTransport.wss,
        allowBadCertificate: false,
      );
    } else {
      final expireSeconds = int.tryParse(
            _expireSecondsController.text.trim(),
          ) ??
          SipAccount.defaultRegistrationExpireSeconds;

      if (widget.isEditing) {
        saved = await widget.controller.updateAccount(
          accountId: widget.initialAccount!.id,
          displayName: _displayNameController.text,
          username: _usernameController.text,
          authorizationUser: _authorizationUserController.text,
          password: _passwordController.text,
          domain: _domainController.text,
          signalingAddress: _signalingAddressController.text,
          transport: _transport,
          allowBadCertificate:
              _transport == SipTransport.wss && _allowBadCertificate,
          outboundProxy: _outboundProxyController.text,
          stunServer: _stunServerController.text,
          registrationExpireSeconds: expireSeconds,
        );
      } else {
        saved = await widget.controller.addAccount(
          displayName: _displayNameController.text,
          username: _usernameController.text,
          authorizationUser: _authorizationUserController.text,
          password: _passwordController.text,
          domain: _domainController.text,
          signalingAddress: _signalingAddressController.text,
          transport: _transport,
          allowBadCertificate:
              _transport == SipTransport.wss && _allowBadCertificate,
          outboundProxy: _outboundProxyController.text,
          stunServer: _stunServerController.text,
          registrationExpireSeconds: expireSeconds,
        );
      }
    }

    if (!context.mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
    });

    if (saved) {
      Navigator.of(context).pop();
    }
  }
}

enum _AccountFormMode { inteliex, manual }

String _transportLabel(SipTransport transport) {
  return switch (transport) {
    SipTransport.udp => 'UDP',
    SipTransport.ws => 'WS',
    SipTransport.wss => 'WSS',
    SipTransport.tcp => 'TCP',
  };
}

String _defaultAddressFor(SipTransport transport) {
  return switch (transport) {
    SipTransport.udp => 'pbx.example.com:5060',
    SipTransport.ws => 'ws://pbx.example.com:8088/ws',
    SipTransport.wss => 'wss://pbx.example.com:8089/ws',
    SipTransport.tcp => 'pbx.example.com:5060',
  };
}

String _addressLabelFor(SipTransport transport) {
  return switch (transport) {
    SipTransport.udp => 'UDP sunucu adresi',
    SipTransport.ws => 'WS adresi',
    SipTransport.wss => 'WSS adresi',
    SipTransport.tcp => 'TCP sunucu adresi',
  };
}

String _addressHintFor(SipTransport transport) {
  return switch (transport) {
    SipTransport.udp => 'pbx.example.com:5060',
    SipTransport.ws => 'ws://pbx.example.com:8088/ws',
    SipTransport.wss => 'wss://pbx.example.com:8089/ws',
    SipTransport.tcp => 'pbx.example.com:5060',
  };
}

String _addressHelperFor(SipTransport transport) {
  return switch (transport) {
    SipTransport.udp =>
      'Klasik SIP santraller icin host:port yazin. Mobilde native SIP katmani uzerinden calisir.',
    SipTransport.ws =>
      'WebRTC olmayan testlerde sifresiz websocket kullanabilirsiniz.',
    SipTransport.wss => 'FreePBX WebRTC kurulumlarinda en yaygin secenektir.',
    SipTransport.tcp =>
      'Duz SIP icin host:port yazin. Ornek: pbx.example.com:5060',
  };
}

String _effectiveAuthUser(SipAccount account) {
  final authUser = account.authorizationUser.trim();
  if (authUser.isNotEmpty) {
    return authUser;
  }

  return account.username.trim();
}

bool _looksLikeSwappedIdentity(SipAccount account) {
  final displayName = account.displayName.trim();
  final username = account.username.trim();
  if (displayName.isEmpty || username.isEmpty) {
    return false;
  }

  final displayLooksNumeric = RegExp(r'^\d+$').hasMatch(displayName);
  final usernameLooksLabel = RegExp(r'[A-Za-z_-]').hasMatch(username);
  return displayLooksNumeric && usernameLooksLabel;
}

class _OnboardingView extends StatelessWidget {
  const _OnboardingView({required this.controller});

  final SoftphoneController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.call_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'SIP hesabı ekleyin',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Gelen ve giden çağrı alabilmek için önce bir SIP hesabı tanımlayın.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF51625C),
                ),
              ),
              const SizedBox(height: 24),
              _OnboardingCard(
                icon: Icons.verified_user_outlined,
                title: 'Inteliex ile giriş',
                description:
                    'Inteliex abonesiyseniz sunucu adresi, kullanıcı ve şifre yeterli. Rehber otomatik çekilir.',
                onTap: () => _showAccountSheet(
                  context,
                  controller,
                  initialMode: _AccountFormMode.inteliex,
                ),
                primary: true,
              ),
              const SizedBox(height: 12),
              _OnboardingCard(
                icon: Icons.settings_ethernet,
                title: 'Manuel SIP hesabı',
                description:
                    'Herhangi bir SIP sağlayıcısı için transport, domain ve bağlantı bilgilerini elle girin.',
                onTap: () => _showAccountSheet(
                  context,
                  controller,
                  initialMode: _AccountFormMode.manual,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = primary
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = primary
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: foreground.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
