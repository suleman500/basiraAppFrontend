import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:projctlitudei/core/theme/app_colors.dart';

import '../../models/detected_object.dart';

// ============================================================
// أزرار الشريط العلوي
// ============================================================

/// زر دائري زجاجي (44×44).
class HudIconButton extends StatelessWidget {
  const HudIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color = AppColors.onSurface,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(
            side: BorderSide(color: AppColors.glassBorder),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                size: 22,
                color: onPressed == null ? color.withValues(alpha: 0.35) : color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// زر كبسولة صغير (يُستخدم لتبديل اللغة AR/EN).
class HudPillButton extends StatelessWidget {
  const HudPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.glassBorder),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(icon, size: 18, color: AppColors.onSurface),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// الشريط العلوي: رجوع + عنوان + (صوت، لغة، تبديل كاميرا، مسح ذاكرة).
class HudTopBar extends StatelessWidget {
  const HudTopBar({
    super.key,
    required this.voiceEnabled,
    required this.languageLabel,
    required this.canSwitchCamera,
    required this.onBack,
    required this.onToggleVoice,
    required this.onToggleLanguage,
    required this.onSwitchCamera,
    required this.onClearMemory,
  });

  final bool voiceEnabled;
  final String languageLabel;
  final bool canSwitchCamera;
  final VoidCallback onBack;
  final VoidCallback onToggleVoice;
  final VoidCallback onToggleLanguage;
  final VoidCallback onSwitchCamera;
  final VoidCallback onClearMemory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          HudIconButton(
            icon: Icons.arrow_back,
            tooltip: 'رجوع',
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'الكشف المباشر',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          HudIconButton(
            icon: voiceEnabled ? Icons.volume_up : Icons.volume_off,
            tooltip: voiceEnabled ? 'كتم الصوت' : 'تفعيل الصوت',
            onPressed: onToggleVoice,
            color: voiceEnabled ? AppColors.primary : AppColors.onSurface,
          ),
          const SizedBox(width: 6),
          HudPillButton(
            label: languageLabel,
            icon: Icons.translate,
            tooltip: 'تبديل اللغة',
            onPressed: onToggleLanguage,
          ),
          const SizedBox(width: 6),
          HudIconButton(
            icon: Icons.cameraswitch,
            tooltip: 'تبديل الكاميرا',
            onPressed: canSwitchCamera ? onSwitchCamera : null,
          ),
          const SizedBox(width: 6),
          HudIconButton(
            icon: Icons.delete_sweep,
            tooltip: 'مسح ذاكرة الأجسام',
            onPressed: onClearMemory,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// شارة الحالة فوق الكاميرا
// ============================================================

class HudStatusPill extends StatelessWidget {
  const HudStatusPill({
    super.key,
    required this.label,
    this.color = AppColors.primary,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// شريط الأجسام المرصودة
// ============================================================

class HudObjectsRow extends StatelessWidget {
  const HudObjectsRow({
    super.key,
    required this.detections,
    required this.labelTranslator,
    required this.proximityLabels,
    this.touchedKey,
  });

  final List<DetectedObject> detections;
  final String Function(String englishLabel) labelTranslator;
  final Map<String, String> proximityLabels;
  final String? touchedKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'الأجسام المرصودة فوريًا (${detections.length})',
                style: const TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 60,
            child: detections.isEmpty
                ? const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'لا توجد أشياء مكتشفة حاليًا',
                style: TextStyle(
                  color: AppColors.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
            )
                : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: detections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final obj = detections[index];
                final isTouched =
                    touchedKey != null && obj.trackingKey == touchedKey;
                final proximity = proximityLabels[obj.label];
                final confidence =
                    '${(obj.confidence * 100).toStringAsFixed(0)}%';
                final subtitle = proximity != null
                    ? '$confidence • $proximity'
                    : confidence;

                return _ObjectChip(
                  title: labelTranslator(obj.label),
                  subtitle: subtitle,
                  highlighted: isTouched,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectChip extends StatelessWidget {
  const _ObjectChip({
    required this.title,
    required this.subtitle,
    required this.highlighted,
  });

  final String title;
  final String subtitle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final bg = highlighted ? AppColors.primary : AppColors.surfaceHigh;
    final fg = highlighted ? AppColors.onPrimary : AppColors.onSurface;
    final sub = highlighted
        ? AppColors.onPrimary.withValues(alpha: 0.75)
        : AppColors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted ? Colors.transparent : AppColors.glassBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: highlighted ? AppColors.onPrimary : AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(subtitle, style: TextStyle(color: sub, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// لوحة الأمر الصوتي (موجات + النص المسموع)
// ============================================================

class HudVoicePanel extends StatefulWidget {
  const HudVoicePanel({
    super.key,
    required this.isListening,
    required this.text,
  });

  final bool isListening;
  final String text;

  @override
  State<HudVoicePanel> createState() => _HudVoicePanelState();
}

class _HudVoicePanelState extends State<HudVoicePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isListening) _wave.repeat();
  }

  @override
  void didUpdateWidget(covariant HudVoicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !_wave.isAnimating) {
      _wave.repeat();
    } else if (!widget.isListening && _wave.isAnimating) {
      _wave.stop();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shownText = widget.text.isEmpty ? 'استمع...' : '“${widget.text}”';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(
            color: Color(0xA6000000),
            blurRadius: 32,
            spreadRadius: -4,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.graphic_eq, size: 18, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                widget.isListening ? 'جاري الاستماع…' : 'آخر أمر صوتي',
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 32,
                child: AnimatedBuilder(
                  animation: _wave,
                  builder: (context, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(12, (i) {
                        final height = widget.isListening
                            ? 6 +
                            26 *
                                (0.5 +
                                    0.5 *
                                        math.sin(
                                          _wave.value * 2 * math.pi +
                                              i * 0.7,
                                        ))
                            : 6.0;
                        return Container(
                          width: 4,
                          height: height,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i.isEven
                                ? AppColors.secondary
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            shownText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              height: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// بلاطات الإجراءات (كشف حي / عمق / مساحة / توجيه)
// ============================================================

class HudActionTile extends StatelessWidget {
  const HudActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.active = false,
    this.warning = false,
    this.loading = false,
    this.dimmed = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onPressed;

  /// مفعّل: خلفية خضراء.
  final bool active;

  /// تحذير/إلغاء: خلفية كهرمانية.
  final bool warning;

  /// يعرض مؤشر تحميل بدل الأيقونة.
  final bool loading;

  /// باهت بصريًا فقط — يبقى قابلًا للضغط (الدوال نفسها تنطق سبب الرفض).
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final filled = active || warning;
    final bg = warning
        ? AppColors.tertiary
        : (active ? AppColors.primary : AppColors.surface);
    final fg = filled ? AppColors.onPrimary : AppColors.onSurface;
    final iconColor = filled ? AppColors.onPrimary : AppColors.primary;

    return Semantics(
      button: true,
      label: subtitle == null ? label : '$label، $subtitle',
      excludeSemantics: true,
      child: Opacity(
        opacity: dimmed ? 0.5 : 1,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Container(
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: filled ? Colors.transparent : AppColors.glassBorder,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (loading)
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: iconColor,
                      ),
                    )
                  else
                    Icon(icon, size: 26, color: iconColor),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (subtitle != null)
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        subtitle!,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.75),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// زر المايك الكبير (اضغط مطوّلًا)
// ============================================================

class HudMicButton extends StatefulWidget {
  const HudMicButton({
    super.key,
    required this.isListening,
    required this.isAvailable,
    required this.onPressDown,
    required this.onPressUp,
    required this.onPressCancel,
  });

  final bool isListening;
  final bool isAvailable;
  final VoidCallback onPressDown;
  final VoidCallback onPressUp;
  final VoidCallback onPressCancel;

  @override
  State<HudMicButton> createState() => _HudMicButtonState();
}

class _HudMicButtonState extends State<HudMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isListening) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant HudMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isListening && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.isListening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color core = widget.isListening
        ? AppColors.secondary
        : (widget.isAvailable ? AppColors.primary : AppColors.surfaceHighest);
    final Color iconColor = widget.isAvailable || widget.isListening
        ? AppColors.onPrimary
        : AppColors.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'اضغط مطوّلًا واسأل بصوتك',
          excludeSemantics: true,
          child: Listener(
            onPointerDown: (_) => widget.onPressDown(),
            onPointerUp: (_) => widget.onPressUp(),
            onPointerCancel: (_) => widget.onPressCancel(),
            child: SizedBox(
              width: 96,
              height: 96,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      if (widget.isListening)
                        Container(
                          width: 72 + 24 * _pulse.value,
                          height: 72 + 24 * _pulse.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.secondary.withValues(
                                alpha: 0.6 * (1 - _pulse.value),
                              ),
                              width: 3,
                            ),
                          ),
                        ),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: core,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: core.withValues(alpha: 0.4),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Icon(Icons.mic, size: 36, color: iconColor),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.isListening ? 'جاري الاستماع…' : 'اضغط مطوّلًا للتحدث',
          style: const TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}