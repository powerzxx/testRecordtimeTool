function Get-UserGuideTopics {
    return @(
        [pscustomobject]@{ Title = '快速开始'; Body = @'
1. 点击“打开记录文件”或“新建记录文件”，选择本次测试使用的文本文件。

2. 在“按钮名称”中输入操作名称，按 Enter 或点击“添加按钮”。可连续输入并按 Enter 添加多个按钮。

3. 从左侧把按钮拖入右侧“测试步骤”，上下拖动安排执行顺序。同一个按钮可以拖入多次。

4. 添加结束后按 Esc，或点击空白处退出输入框。黄色按钮是下一步。

5. 每按一次空格，记录一步及按键时刻的时间。完成全部步骤后自动进入下一轮，可继续按空格循环测试。

查看本说明不会新增记录或改变测试进度。关闭说明后可继续测试。
'@ }
        [pscustomobject]@{ Title = '快捷键与输入'; Body = @'
空格：执行测试区的下一步，长按不会连续记录。文本框和方案下拉框内的空格不触发测试。

F8：立即标记异常，不推进步骤。可稍后编辑异常行补充说明。

Ctrl+Z：撤销最近一次空格记录，同时恢复轮次与步骤。输入框内保留文字撤销功能，不撤销测试记录。

Enter：名称框内添加按钮；记录编辑框内保存修改。添加按钮后焦点留在名称框，方便连续添加。

Esc：退出名称输入或方案选择，返回测试；记录编辑框内用于取消编辑。说明窗口内用于关闭说明。

点击空白处或普通文字标签：退出输入焦点，返回测试。尚未保存的记录编辑文字会保留。点击按钮、输入框和勾选项仍执行各自操作。

以上测试快捷键仅在主窗口中生效。查看说明或操作其他弹窗时不会触发测试记录。
'@ }
        [pscustomobject]@{ Title = '按钮与测试方案'; Body = @'
添加按钮：输入名称后按 Enter 或点击“添加按钮”。按钮保持原名称，不额外添加序号。

按钮管理：右键左侧按钮，可上移、下移、重命名或删除。重命名、删除会同步更新测试区内对应的步骤。

自动保存：新增、重命名、排序、删除按钮，以及拖入、排序、移除或清空测试步骤，都会自动保存当前方案。“保存按钮配置”可手动保存或在失败后重试。

另存方案：将当前按钮和步骤组合保存为一个方案。覆盖同名的其他方案需要确认。

切换方案：使用“测试方案”下拉框。切换后从第 1 轮、第 1 步开始，已有记录保留。

清空当前配置：确认后清空当前方案的按钮和步骤，其他方案和已有记录保留。

重新打开工具会恢复保存的方案与步骤，但执行进度从第 1 轮开始。
'@ }
        [pscustomobject]@{ Title = '测试步骤与轮次'; Body = @'
右侧按钮按从上到下的顺序执行。黄色表示下一步，浅绿色表示本轮已完成；下方显示轮次、下一步位置和名称。长名称可悬停查看。

每次空格只记录一步。最后一步记录成功后，显示下一轮的第 1 步。鼠标点击任意操作按钮仅记录该操作，不推进空格执行进度。

重做本轮：轮次不变，返回第 1 步，等待按空格。

开始下一轮：当前显示的轮次加 1，放弃本轮剩余步骤，返回第 1 步。

全部重来：返回第 1 轮、第 1 步。

以上三个按钮都保留已有记录，点击时不新增记录。每轮首次写入时会添加轮次标题，不额外写入重做或跳轮标记。

拖动调整步骤不会重置轮次。测试中新增步骤时，插在原下一步之前的留到下一轮，插在其后的本轮执行；本轮尚未开始时，按完整顺序执行。已完成步骤不会因排序重复执行。

右键步骤可移除。删除下一步后继续剩余步骤；若删除了全部待执行步骤，下次空格开始下一轮。

清空步骤：移除测试区所有按钮，保留轮次、左侧按钮和已有记录，并自动保存。
'@ }
        [pscustomobject]@{ Title = '异常标记与撤销'; Body = @'
标记异常 · F8

按 F8 立即写入当时时间和“[异常] 待补充说明”。异常行显示为红字，稍后可在该行点击“编辑”补充说明。不推进步骤、不改变轮次，也不改变记录间隔的计时起点。长按 F8 不会连发。

撤销空格 · Ctrl+Z

用于纠正误按空格：撤销最近一次空格记录，恢复当时的轮次、下一步、已完成状态和间隔计时起点。跨轮时可恢复到上一轮；本次新增的轮次标题也会一并撤销。

仅保留一次撤销机会。后续手动记录、异常记录、编辑或删除记录、变更步骤、切换方案或文件、重置轮次，都会使原撤销失效。

如有正在编辑的记录，请先保存或取消编辑。记录文件被其他程序修改后，不会执行撤销，以免覆盖外部更改。

文本输入框内的 Ctrl+Z 用于撤销文字。按 Esc 或点击空白处退出输入后，再用 Ctrl+Z 撤销测试记录。
'@ }
        [pscustomobject]@{ Title = '记录编辑与时间'; Body = @'
记录立即追加到当前文件，无需另行保存记录。

鼠标移到记录行可显示编辑和删除按钮。点击“编辑”后修改文字，按 Enter 或点击保存；按 Esc 或点击取消放弃修改。轮次标题不支持文字编辑。

删除记录后可在 5 秒内撤销删除。“撤销删除”与 Ctrl+Z 撤销空格是两个独立功能。

毫秒时间：勾选后，新记录使用 HH:mm:ss.fff；未勾选时使用 HH:mm:ss。已有记录格式不变，两种格式都支持编辑。

记录间隔：勾选后，新操作记录附带距上一次操作的秒数。异常标记不改变计时起点。

重做本轮、全部重来、开始下一轮、切换文件或方案后，间隔计时重新开始；自动循环时继续计算连续操作的间隔。

时间选项会自动保存，下次启动恢复。
'@ }
        [pscustomobject]@{ Title = '文件与备份'; Body = @'
打开记录文件：载入已有文件，后续记录继续追加。新建记录文件：选择本次使用的新文件。切换文件时进度从第 1 轮、第 1 步开始。

查看当前文件：使用系统默认应用打开记录。打开文件夹：打开当前文件所在目录。

打开和新建文件的对话框会记住上次目录。

清空记录：需要确认。程序先生成带时间的 .txt 完整备份并送入 Windows 回收站，确认备份完整后才清空当前文件，并重置轮次与步骤。备份或回收失败时不清空原记录。

备份命名示例：耳机操作记录_2026-10-22_14-30-25-123.txt。需要恢复时，在回收站找到对应名称，右键“还原”，备份会回到原记录目录。带时间的备份与当前记录文件分别保留，当前记录文件继续用于测试。

还原后的备份可直接用记事本打开，或通过“打开记录文件”载入。选为当前文件后，新记录也会追加到该备份文件。清空回收站会删除其中的备份。

按钮配置和测试方案会自动保存，不依赖记录文件。清空步骤或配置不会清空已有记录。
'@ }
        [pscustomobject]@{ Title = '窗口与状态'; Body = @'
设置 → 界面布局：可选择“经典布局”或“精简工作台”，立即切换，并记住选择。首次使用默认为经典布局。

切换时保留当前文件、测试方案、轮次、步骤、撤销机会，以及输入框内尚未添加的名称和未保存的记录编辑文字，不会新增记录。

经典布局：操作按钮集中在上方，记录区在下方。上下拖动横向分隔线，可分配测试区和记录区高度。

精简工作台：文件操作、方案和按钮管理在顶部菜单；窗口置顶、提示音、间隔和毫秒选项在“设置”菜单。左侧显示方案、操作按钮和记录，右侧整列显示测试步骤。左右拖动竖向分隔线调整测试区宽度，上下拖动左侧横向分隔线调整按钮区与记录区高度。

两种布局分别记住分隔线比例，共用窗口位置与大小。内容较多时可滚动查看。

关闭时保存窗口位置、大小、最大化状态和分隔线比例，下次打开恢复。更换显示器后会将窗口调整到可见范围。

窗口置顶：使工具保持在其他普通窗口上方。记录时提示音：每次成功写入时播放提示音。

置顶时，另存方案、重命名、确认提示和文件选择窗口会显示在主窗口前方，关闭弹窗后仍保留置顶设置。

点击“查看当前文件”或“打开文件夹”后，工具会暂时让出置顶，方便使用外部窗口；回到或点击本工具后自动恢复，期间置顶选项仍保持勾选。如果主动取消勾选，则不会自动重新开启置顶。打开失败时恢复之前的状态。

底部仅显示当前状态，如正在输入按钮名称、正在编辑记录、尚未选择记录文件、尚无测试步骤或可按空格测试。

“可按空格测试”表示当前焦点允许执行步骤；若仍在输入名称，可按 Esc 或点击空白处返回测试。
'@ }
    )
}

function New-UserGuideDialog {
    $guide = New-Object Windows.Forms.Form
    $guide.Text = '使用说明 · 耳机 Log 时间记录'
    $guide.StartPosition = 'CenterParent'
    $guide.ShowInTaskbar = $false
    $guide.MinimizeBox = $false
    $guide.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10)
    $guide.AutoScaleMode = 'Dpi'
    $guide.ClientSize = New-Object Drawing.Size(820, 560)
    $guide.MinimumSize = New-Object Drawing.Size(680, 460)

    $guideLayout = New-Object Windows.Forms.TableLayoutPanel
    $guideLayout.Dock = 'Fill'; $guideLayout.Padding = New-Object Windows.Forms.Padding(12)
    $guideLayout.ColumnCount = 2; $guideLayout.RowCount = 2
    $guideLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Absolute', 180))) | Out-Null
    $guideLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle('Percent', 100))) | Out-Null
    $guideLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Percent', 100))) | Out-Null
    $guideLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle('Absolute', 44))) | Out-Null
    $guide.Controls.Add($guideLayout)

    $topicList = New-Object Windows.Forms.ListBox
    $topicList.Name = 'GuideTopics'; $topicList.Dock = 'Fill'
    $topicList.IntegralHeight = $false; $topicList.ItemHeight = 30
    $topicList.DisplayMember = 'Title'
    foreach ($topic in (Get-UserGuideTopics)) { $topicList.Items.Add($topic) | Out-Null }
    $guideLayout.Controls.Add($topicList, 0, 0)

    $content = New-Object Windows.Forms.TextBox
    $content.Name = 'GuideContent'; $content.Dock = 'Fill'
    $content.Multiline = $true; $content.WordWrap = $true
    $content.ReadOnly = $true; $content.BackColor = [Drawing.Color]::White
    $content.BorderStyle = 'None'
    $content.ScrollBars = 'Vertical'; $content.Margin = New-Object Windows.Forms.Padding(12, 3, 3, 3)
    $guideLayout.Controls.Add($content, 1, 0)
    $topicList.Tag = $content
    $topicList.Add_SelectedIndexChanged({
        param($sender, $eventArgs)
        if ($null -ne $sender.SelectedItem) {
            $sender.Tag.Text = $sender.SelectedItem.Title + "`r`n`r`n" + ($sender.SelectedItem.Body -replace '\r?\n', "`r`n")
            $sender.Tag.Select(0, 0)
            $sender.Tag.ScrollToCaret()
        }
    })

    $close = New-Object Windows.Forms.Button
    $close.Text = '关闭'; $close.AutoSize = $true; $close.Anchor = 'Right'
    $close.DialogResult = 'Cancel'
    $guideLayout.Controls.Add($close, 1, 1)
    $guide.CancelButton = $close
    $topicList.SelectedIndex = 0
    return $guide
}

function Show-UserGuide {
    $guide = New-UserGuideDialog
    $guide.TopMost = $form.TopMost
    try { Show-RecorderModalDialog -Dialog $guide | Out-Null }
    finally { $guide.Dispose() }
}
