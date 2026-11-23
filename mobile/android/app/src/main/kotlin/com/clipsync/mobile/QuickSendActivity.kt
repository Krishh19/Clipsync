package com.clipsync.mobile

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

class QuickSendActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            handleClipboard()
            finish()
        }
    }

    private fun handleClipboard() {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager
        if (clipboard == null || !clipboard.hasPrimaryClip()) {
            Toast.makeText(this, "Clipboard is empty", Toast.LENGTH_SHORT).show()
            return
        }

        val clip = clipboard.primaryClip
        if (clip == null || clip.itemCount == 0) {
            Toast.makeText(this, "Clipboard is empty", Toast.LENGTH_SHORT).show()
            return
        }

        val item = clip.getItemAt(0)
        val text = item.text?.toString() ?: item.coerceToText(this)?.toString()
        val uri = item.uri

        val sendIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }

        if (uri != null) {
            val mimeType = contentResolver.getType(uri) ?: "*/*"
            sendIntent.type = mimeType
            sendIntent.putExtra(Intent.EXTRA_STREAM, uri)
            sendIntent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(sendIntent)
        } else if (!text.isNullOrEmpty()) {
            sendIntent.type = "text/plain"
            sendIntent.putExtra(Intent.EXTRA_TEXT, text)
            startActivity(sendIntent)
        } else {
            Toast.makeText(this, "No sendable content in clipboard", Toast.LENGTH_SHORT).show()
        }
    }
}
