import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/sync.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../widgets/common.dart';
import 'van_sales.dart';

/// Fiche d'un point de vente (vente en camionnette) : ce que le client doit, le crédit
/// encore possible, et l'encaissement d'un paiement (même sans réseau).
class OutletCreditSection extends ConsumerWidget {
  const OutletCreditSection({
    super.key,
    required this.outletId,
    required this.outletName,
  });

  final String outletId;
  final String outletName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(outletBalanceProvider(outletId)).value;
    if (b == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Crédit et paiements'),
        SurfaceCard(
          semanticLabel: 'Crédit et paiements',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _Figure(
                      label: 'Doit',
                      value: formatMoney(b.outstanding),
                      color: b.outstanding > 0
                          ? toneColor(context, Tone.warning)
                          : null,
                    ),
                  ),
                  Expanded(
                    child: _Figure(
                      label: 'Crédit possible',
                      value: b.creditAllowed
                          ? formatMoney(b.available)
                          : 'Pas de crédit',
                    ),
                  ),
                ],
              ),
              if (b.creditAllowed) ...[
                const SizedBox(height: Space.xs),
                Text(
                  'Plafond : ${formatMoney(b.creditLimit!)}',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (b.outstanding > 0) ...[
                const SizedBox(height: Space.md),
                PillButton(
                  label: 'Encaisser un paiement',
                  icon: Icons.payments_outlined,
                  style: PillStyle.tonal,
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => _PaymentSheet(
                      outletId: outletId,
                      outletName: outletName,
                      owed: b.outstanding,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Paiement reçu : il règle les ventes dues du client, les plus anciennes d'abord.
class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({
    required this.outletId,
    required this.outletName,
    required this.owed,
  });

  final String outletId;
  final String outletName;
  final num owed;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final _amount = TextEditingController(
    text: widget.owed.round().toString(),
  );
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = num.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Saisissez le montant reçu.');
      return;
    }
    if (amount > widget.owed) {
      setState(
        () => _error =
            'Le client ne doit que ${formatMoney(widget.owed)} : vérifiez le montant.',
      );
      return;
    }
    tapFeedback();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final outcome = await sendPayment(
        ref,
        outletId: widget.outletId,
        outletName: widget.outletName,
        amount: amount,
        method: _method,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showMessage(
        context,
        outcome == SubmitOutcome.queued
            ? 'Paiement enregistré sur le téléphone : envoyé au retour du réseau.'
            : 'Paiement de ${formatMoney(amount)} enregistré.',
      );
    } catch (error) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = ApiException.from(error).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Space.page,
        Space.lg,
        Space.page,
        Space.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Paiement de ${widget.outletName}', style: text.titleLarge),
          Text(
            'Doit ${formatMoney(widget.owed)} : le paiement règle ses ventes, les plus anciennes d’abord.',
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Space.md),
            InfoBanner(
              icon: Icons.error_outline_rounded,
              tone: Tone.danger,
              message: _error!,
            ),
          ],
          const SizedBox(height: Space.md),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Montant reçu',
              suffixText: 'F CFA',
            ),
          ),
          const SizedBox(height: Space.md),
          AppSegmented<PaymentMethod>(
            segments: {for (final m in PaymentMethod.values) m: m.label},
            selected: _method,
            onChanged: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: Space.lg),
          PillButton(
            label: 'Enregistrer le paiement',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
