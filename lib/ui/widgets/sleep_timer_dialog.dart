import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../services/sleep_timer_service.dart';
import '../theme/app_theme.dart';

/// Modal dialog for configuring Sleep Timer.
class SleepTimerDialog extends StatelessWidget {
  const SleepTimerDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final timerService = SleepTimerService();

    return StreamBuilder<int>(
      stream: timerService.remainingSecondsStream,
      initialData: timerService.remainingSeconds,
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? 0;
        final isActive = timerService.isActive;

        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: const [
              Icon(CupertinoIcons.moon_zzz_fill, color: AppTheme.secondary),
              SizedBox(width: 10),
              Text('ตั้งเวลาปิดเพลง (Sleep Timer)', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        remaining == -1
                            ? 'ปิดเมื่อเล่นเพลงนี้จบ'
                            : 'เหลือเวลาอีก: ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      TextButton(
                        child: const Text('ยกเลิก', style: TextStyle(color: Colors.redAccent)),
                        onPressed: () {
                          timerService.cancelTimer();
                        },
                      ),
                    ],
                  ),
                ),
              ],
              _buildOption(context, '15 นาที', () => timerService.startTimer(15)),
              _buildOption(context, '30 นาที', () => timerService.startTimer(30)),
              _buildOption(context, '45 นาที', () => timerService.startTimer(45)),
              _buildOption(context, '60 นาที (1 ชั่วโมง)', () => timerService.startTimer(60)),
              _buildOption(context, 'เมื่อเล่นเพลงปัจจุบันจบ', () => timerService.setStopAtEndOfTrack()),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('ปิด', style: TextStyle(color: Colors.white54)),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOption(BuildContext context, String title, VoidCallback onTap) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white70)),
      trailing: const Icon(CupertinoIcons.chevron_forward, color: Colors.white24, size: 16),
      onTap: () {
        onTap();
        Navigator.pop(context);
      },
    );
  }
}
