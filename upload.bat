@echo off
setlocal enabledelayedexpansion

:: ========== 用户配置区域 ==========
:: 1. 你的 GitHub 用户名
set GITHUB_USER=1127924631

:: 2. 你在 GitHub 上用于【实际存储 CDN 静态资源文件】的仓库名
set GITHUB_REPO_NAME=1127924631cdn

:: 3. 本地存放【待上传静态资源】并作为【Git 工作目录】的文件夹路径
set LOCAL_GIT_AND_ASSETS_DIR=E:\application\tool\1127924631cdn
:: 注意：这个目录现在既是资源暂存区，也是 Git 仓库的本地克隆

:: 4. 你要推送到的分支名
set GIT_BRANCH=main
:: ========== 配置结束 ==========

echo Verifying GitHub CLI authentication...
gh auth status
IF !ERRORLEVEL! NEQ 0 (
    echo GitHub CLI authentication failed or gh is not found.
    pause
    exit /b !ERRORLEVEL!
)

echo Checking if asset directory "%LOCAL_GIT_AND_ASSETS_DIR%" exists...
if not exist "%LOCAL_GIT_AND_ASSETS_DIR%" (
    echo Asset and Git directory "%LOCAL_GIT_AND_ASSETS_DIR%" not found!
    echo Please ensure this is a valid Git repository clone.
    pause
    exit /b 1
)

:: 进入 Git 仓库目录
echo Changing to Git repository directory: "%LOCAL_GIT_AND_ASSETS_DIR%"
cd /d "%LOCAL_GIT_AND_ASSETS_DIR%"
IF !ERRORLEVEL! NEQ 0 (
    echo Failed to change to Git repository directory.
    pause
    exit /b !ERRORLEVEL!
)

:: （可选）拉取最新更改，以防万一远程有更新
echo Pulling latest changes from remote...
git pull origin %GIT_BRANCH%
IF !ERRORLEVEL! NEQ 0 (
    echo Failed to pull from Git repository. Check for conflicts or network issues.
    pause
    exit /b !ERRORLEVEL!
)

:: 检查是否有文件可提交 (如果没有新文件或更改，commit 会失败)
echo Adding all files to Git...
git add .

:: 检查 git status，看是否有东西被 add
git status
for /f "tokens=*" %%s in ('git status --porcelain') do (
  set HAS_CHANGES_TO_COMMIT=1
  goto :changes_found
)
set HAS_CHANGES_TO_COMMIT=0
:changes_found

if %HAS_CHANGES_TO_COMMIT% EQU 0 (
    echo No new files or changes detected in "%LOCAL_GIT_AND_ASSETS_DIR%".
    echo If you intended to update existing files for a new release tag,
    echo ensure they are modified or make a small change to trigger a commit.
    echo Or, we can proceed to tag the current commit if it's what you want.
    set /p PROCEED_WITHOUT_COMMIT="No changes to commit. Proceed to tag current HEAD and release? (Y/N): "
    if /i not "!PROCEED_WITHOUT_COMMIT!"=="Y" (
        echo Aborting.
        pause
        exit /b 1
    )
)

:: 生成唯一标签名和 Release/Commit 信息 (基于时间戳)
for /f "tokens=2 delims==" %%I in ('"wmic os get localdatetime /value"') do set datetime=%%I
set TS_SUFFIX=%datetime:~0,4%%datetime:~4,2%%datetime:~6,2%_%datetime:~8,2%%datetime:~10,2%%datetime:~12,2%
set GIT_TAG_NAME=cdn-!TS_SUFFIX!
set COMMIT_MESSAGE="CDN assets update - !TS_SUFFIX!"
set RELEASE_TITLE=CDN Assets !TS_SUFFIX!
set RELEASE_NOTES=Automated release of CDN assets. Files are part of the Git tag tree.

if %HAS_CHANGES_TO_COMMIT% EQU 1 (
    echo Committing changes...
    git commit -m %COMMIT_MESSAGE%
    IF !ERRORLEVEL! NEQ 0 (
        echo Failed to commit changes.
        pause
        exit /b !ERRORLEVEL!
    )
)

echo Pushing changes to GitHub branch '%GIT_BRANCH%'...
git push origin %GIT_BRANCH%
IF !ERRORLEVEL! NEQ 0 (
    echo Failed to push changes to branch '%GIT_BRANCH%'.
    pause
    exit /b !ERRORLEVEL!
)

echo Creating Git tag: !GIT_TAG_NAME!
git tag !GIT_TAG_NAME!
IF !ERRORLEVEL! NEQ 0 (
    echo Failed to create Git tag !GIT_TAG_NAME!. It might already exist.
    pause
    exit /b !ERRORLEVEL!
)

echo Pushing Git tag !GIT_TAG_NAME! to GitHub...
git push origin !GIT_TAG_NAME!
IF !ERRORLEVEL! NEQ 0 (
    echo Failed to push Git tag !GIT_TAG_NAME!.
    pause
    exit /b !ERRORLEVEL!
)

echo Creating GitHub Release !GIT_TAG_NAME!...
:: 注意：这里不再需要传递文件列表给 gh release create 来上传附件，
:: 因为文件已经通过 git push 包含在标签指向的提交中了。
:: --latest 可以将此 release 标记为最新版
gh release create !GIT_TAG_NAME! --repo %GITHUB_USER%/%GITHUB_REPO_NAME% --title "!RELEASE_TITLE!" --notes "!RELEASE_NOTES!" --latest
IF !ERRORLEVEL! NEQ 0 (
    echo Failed to create GitHub Release. It might be that the tag was not pushed successfully.
    pause
    exit /b !ERRORLEVEL!
)

echo.
echo ----- SUCCESS! -----
echo Release '!RELEASE_TITLE!' created successfully.
echo Files are now available via jsDelivr from the Git tag '!GIT_TAG_NAME!'.
echo.
echo CDN Links via jsDelivr:
pushd "%LOCAL_GIT_AND_ASSETS_DIR%"
for %%F in (*) do (
    REM Skip .git directory if listed by *
    if /i not "%%F"==".git" (
        REM Check if %%F is a file, not a directory for jsDelivr link
        if not exist "%%F\" (
            echo https://cdn.jsdelivr.net/gh/%GITHUB_USER%/%GITHUB_REPO_NAME%@!GIT_TAG_NAME!/%%F
        )
    )
)
popd
echo.
echo Reminder: The files are now part of the Git history in this repository.
echo Do not simply delete local files without 'git rm' if you want the CDN to reflect deletions in future updates.

pause
exit /b 0