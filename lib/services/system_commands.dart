import 'dart:io';
import '../models/launch_item.dart';

class SystemCommands {
  static final List<LaunchItem> builtinCommands = [
    LaunchItem(
        id: 'sys_shutdown',
        name: '关机',
        targetPath: 'shutdown',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_restart',
        name: '重启',
        targetPath: 'restart',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_lock',
        name: '锁屏',
        targetPath: 'lock',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_control',
        name: '控制面板',
        targetPath: 'control',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_recycle',
        name: '回收站',
        targetPath: 'recycle_bin',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_this_pc',
        name: '此电脑',
        targetPath: 'this_pc',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_calc',
        name: '计算器',
        targetPath: 'calc',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_notepad',
        name: '记事本',
        targetPath: 'notepad',
        type: ItemType.system),
    LaunchItem(
        id: 'sys_taskmgr',
        name: '任务管理器',
        targetPath: 'taskmgr',
        type: ItemType.system),
  ];

  static void execute(String command) {
    switch (command) {
      case 'shutdown':
        Process.run('shutdown', ['/s', '/t', '0']);
        break;
      case 'restart':
        Process.run('shutdown', ['/r', '/t', '0']);
        break;
      case 'lock':
        Process.run('rundll32', ['user32.dll,LockWorkStation']);
        break;
      case 'control':
        Process.run('control', []);
        break;
      case 'recycle_bin':
        Process.run('explorer', ['shell:RecycleBinFolder']);
        break;
      case 'this_pc':
        Process.run('explorer', ['shell:MyComputerFolder']);
        break;
      case 'calc':
        Process.run('calc', []);
        break;
      case 'notepad':
        Process.run('notepad', []);
        break;
      case 'taskmgr':
        Process.run('taskmgr', []);
        break;
    }
  }
}
