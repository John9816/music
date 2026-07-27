package com.music.player.ui.activity

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.music.player.databinding.ActivityToolsBinding
import com.music.player.databinding.ItemToolHeaderBinding
import com.music.player.databinding.ItemToolRowBinding
import com.music.player.ui.tools.ToolGroup
import com.music.player.ui.tools.ToolItem
import com.music.player.ui.tools.ToolsCatalog
import com.music.player.ui.util.PressFeedback
import com.music.player.ui.util.ThemeManager
import com.music.player.ui.util.applyEdgeToEdge
import com.music.player.ui.util.applyNavigationBarInsetPadding
import com.music.player.ui.util.applyStatusBarInsetPadding
import com.music.player.ui.util.bindPressFeedback

class ToolsActivity : AppCompatActivity() {

    private lateinit var binding: ActivityToolsBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        ThemeManager.prepareActivity(this)
        super.onCreate(savedInstanceState)
        binding = ActivityToolsBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val lightBars = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) !=
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        applyEdgeToEdge(rootView = binding.root, lightSystemBars = lightBars)
        binding.toolbar.applyStatusBarInsetPadding()
        binding.recyclerView.applyNavigationBarInsetPadding()

        binding.toolbar.setNavigationOnClickListener { finish() }
        binding.recyclerView.layoutManager = LinearLayoutManager(this)
        binding.recyclerView.adapter = ToolsAdapter(buildRows()) { item ->
            startActivity(item.intentFactory(this))
        }
    }

    private fun buildRows(): List<Row> {
        val tools = ToolsCatalog.all()
        val rows = mutableListOf<Row>()
        ToolGroup.entries.forEach { group ->
            val items = tools.filter { it.group == group }
            if (items.isEmpty()) return@forEach
            rows += Row.Header(ToolsCatalog.groupTitleRes(group))
            items.forEach { rows += Row.Item(it) }
        }
        return rows
    }

    private sealed class Row {
        data class Header(val titleRes: Int) : Row()
        data class Item(val tool: ToolItem) : Row()
    }

    private class ToolsAdapter(
        private val rows: List<Row>,
        private val onClick: (ToolItem) -> Unit
    ) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

        override fun getItemViewType(position: Int): Int = when (rows[position]) {
            is Row.Header -> 0
            is Row.Item -> 1
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            val inflater = LayoutInflater.from(parent.context)
            return if (viewType == 0) {
                HeaderVH(ItemToolHeaderBinding.inflate(inflater, parent, false))
            } else {
                ItemVH(ItemToolRowBinding.inflate(inflater, parent, false))
            }
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            when (val row = rows[position]) {
                is Row.Header -> (holder as HeaderVH).bind(row.titleRes)
                is Row.Item -> (holder as ItemVH).bind(row.tool, onClick)
            }
        }

        override fun getItemCount(): Int = rows.size

        private class HeaderVH(
            private val binding: ItemToolHeaderBinding
        ) : RecyclerView.ViewHolder(binding.root) {
            fun bind(titleRes: Int) {
                binding.tvHeader.setText(titleRes)
            }
        }

        private class ItemVH(
            private val binding: ItemToolRowBinding
        ) : RecyclerView.ViewHolder(binding.root) {
            fun bind(tool: ToolItem, onClick: (ToolItem) -> Unit) {
                binding.tvTitle.setText(tool.titleRes)
                binding.tvSubtitle.setText(tool.subtitleRes)
                binding.ivIcon.setImageResource(tool.iconRes)
                binding.root.alpha = if (tool.enabled) 1f else 0.5f
                binding.root.bindPressFeedback(PressFeedback.Style.ROW)
                binding.root.setOnClickListener {
                    if (tool.enabled) onClick(tool)
                }
            }
        }
    }

    companion object {
        fun intent(context: Context): Intent = Intent(context, ToolsActivity::class.java)
    }
}
