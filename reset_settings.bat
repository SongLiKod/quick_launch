@echo off
chcp 65001 >nul
title 快速启动 - 重置配置

echo ============================================
echo    快速启动 - 重置配置到默认状态
echo ============================================
echo.

:: 关闭正在运行的程序
taskkill /f /im quick_launch.exe 2>nul
if %errorlevel% equ 0 (
    echo [✓] 已关闭正在运行的快速启动
) else (
    echo [i] 快速启动未在运行
)

:: 清除 SharedPreferences 配置
set "prefs=%LocalAppData%\com.example.quick_launch\shared_preferences.json"
if exist "%prefs%" (
    del /f /q "%prefs%" 2>nul
    echo [✓] 已清除设置缓存
) else (
    echo [i] 未找到设置缓存文件
)

:: 清除应用数据目录
set "appdata_dir=%LocalAppData%\com.example.quick_launch"
if exist "%appdata_dir%" (
    :: 删除除了 logs 外的所有文件，保留日志方便排查
    for %%f in ("%appdata_dir%\*") do (
        if /i not "%%~nxf"=="launch_log.json" del /f /q "%%f" 2>nul
    )
    echo [✓] 已清除应用数据缓存
)

echo.
echo ============================================
echo    重置完成！现在可以重新启动快速启动。
echo ============================================
echo.
pause
