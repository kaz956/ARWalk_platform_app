
import sys
import re

path = '/Users/ichiikazuki/Documents/test/test/FollowHeadWindow.swift'

with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
skip_next = False
for i, line in enumerate(lines):
    if skip_next:
        skip_next = False
        continue

    stripped = line.strip()
    # Check if this line is a comment or a Mojibake-cleaned line we just made
    if stripped.startswith('///') or stripped.startswith('//'):
        next_line = lines[i+1] if i+1 < len(lines) else ""
        indent = line[:line.find(stripped)]
        
        # Mapping logic based on variable/function names
        if 'var origin' in next_line: 
            line = f"{indent}/// スポーン時の位置\n"
        elif 'var axisDir' in next_line: 
            line = f"{indent}/// 移動の軸方向（単位ベクトル）\n"
        elif 'var speed' in next_line: 
            line = f"{indent}/// 基準速度\n"
        elif 'var travelLimit' in next_line: 
            line = f"{indent}/// 最大移動距離\n"
        elif 'var traveled' in next_line: 
            line = f"{indent}/// これまでの移動距離\n"
        elif 'var personalRadius' in next_line: 
            line = f"{indent}/// 個体のパーソナルスペース半径\n"
        elif 'var lateralDir' in next_line: 
            line = f"{indent}/// 横方向のベクトル\n"
        elif 'var lateralOffset' in next_line: 
            line = f"{indent}/// 現在の横オフセット\n"
        elif 'var targetLateralOffset' in next_line: 
            line = f"{indent}/// 目標の横オフセット\n"
        elif 'var maxAvoidanceOffset' in next_line: 
            line = f"{indent}/// 回避の最大幅\n"
        elif 'var avoidanceBias' in next_line: 
            line = f"{indent}/// 回避の優先方向（バイアス）\n"
        elif 'var preferredCruiseOffset' in next_line: 
            line = f"{indent}/// 好みの巡航ライン\n"
        elif 'var yieldFramesRemaining' in next_line: 
            line = f"{indent}/// 譲り（一時停止）の残りフレーム\n"
        elif 'var handContactCooldown' in next_line: 
            line = f"{indent}/// 手接触のクールダウン\n"
        elif 'var isHandContacting' in next_line: 
            line = f"{indent}/// 手が接触中かどうか\n"
        elif 'var hasCountedUserContact' in next_line: 
            line = f"{indent}/// ユーザー接触カウント済みフラグ\n"
        elif 'var collisionSpheres' in next_line: 
            line = f"{indent}/// 衝突判定用の球体配列\n"
        elif 'var stuckFrames' in next_line: 
            line = f"{indent}/// スタック（詰まり）判定用カウンタ\n"
        elif 'var currentSpeed' in next_line: 
            line = f"{indent}/// 現在の補間速度\n"
        elif 'var currentAvoidanceDir' in next_line: 
            line = f"{indent}/// 現在の回避方向\n"
        elif 'var overtakeFrameCount' in next_line: 
            line = f"{indent}/// 追い越し維持用カウンタ\n"
        elif 'var directionChangeCooldown' in next_line: 
            line = f"{indent}/// 進路変更抑制用クールダウン\n"
        elif 'final class RealitySceneData' in next_line: 
            line = f"{indent}/// RealityKitの状態を管理するデータクラス\n"
        elif 'var spawnCountdown' in next_line: 
            line = f"{indent}/// 次のスポーンまでのカウントダウン\n"
        elif 'func addOrUpdateTextEntity' in next_line: 
            line = f"{indent}/// テキストエンティティの追加または更新\n"
        elif 'func addOrUpdateModelEntity' in next_line: 
            line = f"{indent}/// モデルエンティティの追加または更新\n"
        
        # Cleanup remaining Mojibake or previously failed fixes
        if any(ord(c) > 0x7E for c in line) and not any(c in "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン" for c in line):
             if stripped.startswith('///'):
                 line = f"{indent}/// [Cleaned Mojibake]\n"
             else:
                 line = f"{indent}// [Cleaned Mojibake]\n"
        
        # Prevent literal \n if they were accidentally introduced
        line = line.replace("\\n", "\n")
        
        # Deduplicate consecutive identical comments
        if new_lines and new_lines[-1] == line:
            continue

    new_lines.append(line)

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)
